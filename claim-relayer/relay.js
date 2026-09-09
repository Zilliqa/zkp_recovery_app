#!/usr/bin/env node
// Claim relayer — starting point (review & harden before production).
//
// Each run: read new claim entries from the Google Form's linked Sheet (via its public CSV endpoint —
// the sheet is shared "Anyone with the link can view"; no credentials), simulate each against the
// escrow, and submit the ones that would succeed. The relayer key ONLY pays gas — every proof binds
// its own destination (newAddr is a public input), so this script cannot redirect anyone's funds.
//
// The form's calldata field holds the COMPLETE 0x-hex transaction data for the escrow's claim() call.
// Confirmed against the Flutter app (proof_service.dart `encodeCallData`): it is the 4-byte selector
// 0xcf1c9461 = claim(uint256[2],uint256[2][2],uint256[2],uint256[4]) followed by the ABI-encoded proof
// (a,b,c) + 4 public inputs. All args are fixed-size, so it's valid ABI calldata and we send it
// verbatim as tx.data — no ABI/Interface needed here.
//
// Config: environment variables (see .env.example). Run: `node relay.js [--dry-run]`. Cron it for daily runs.

import 'dotenv/config';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { ethers } from 'ethers';
import { openStore } from './store.js';

const sha256 = (s) => createHash('sha256').update(s).digest('hex');

const {
  RPC_URL,
  ESCROW_ADDRESS,
  RELAYER_PRIVATE_KEY,
  SHEET_ID,                       // spreadsheet id, from its URL: /spreadsheets/d/<SHEET_ID>/edit
  SHEET_GID = '0',                // the responses tab's gid (the #gid=… in the URL)
  CALLDATA_COL = 'B',             // column letter holding the calldata (Forms: Timestamp=A, 1st question=B)
  DB_FILE = './relayer.db',       // SQLite per-row state (status/retries/tx hash); replaces the old cursor
  RETRY_MAX = '20',               // give up retrying a "No balance lodged" row after this many attempts
  CALLDATA_FILE,                  // e2e/local testing ONLY: read calldata from this file instead of the Sheet
} = process.env;
const RETRY_LIMIT = parseInt(RETRY_MAX, 10) || 20;

// SHEET_ID is required only for the real Google-Sheet source; CALLDATA_FILE mode doesn't need it.
const required = { RPC_URL, ESCROW_ADDRESS, RELAYER_PRIVATE_KEY, ...(CALLDATA_FILE ? {} : { SHEET_ID }) };
for (const [k, v] of Object.entries(required)) {
  if (!v) { console.error(`Missing required env: ${k}`); process.exit(1); }
}

const DRY_RUN = process.argv.includes('--dry-run') || process.env.DRY_RUN === '1';
const CLAIM_SELECTOR = '0xcf1c9461'; // claim(uint256[2],uint256[2][2],uint256[2],uint256[4])
const CLAIM_HEX_LEN = 778;           // fixed size: '0x' + 4-byte selector + 12×32-byte words = 388 bytes
if (DRY_RUN) console.log('[dry-run] ingest + simulate + report only — no transactions sent, no status writes');

// Public CSV endpoint for a LINK-READABLE sheet (share = "Anyone with the link can view"): the gviz
// query reads the timestamp (column A) + calldata columns for ALL current rows, no auth. Rows are
// deduped by content hash in the DB, so re-reading rows already handled is cheap (INSERT OR IGNORE)
// and deleting/pruning old sheet rows is safe.
const sheetCsvUrl = () =>
  `https://docs.google.com/spreadsheets/d/${SHEET_ID}/gviz/tq?tqx=out:csv&gid=${SHEET_GID}` +
  `&tq=${encodeURIComponent(`select A, ${CALLDATA_COL}`)}`;

// --- Read all current rows: timestamp (column A) + calldata ---
// From a local file (e2e/local testing) if CALLDATA_FILE is set, else the Google Sheet's public CSV.
async function readRows() {
  if (CALLDATA_FILE) {
    // Testing source: one 0x-hex claim() calldata per non-empty line, in submission order (no timestamp).
    const lines = fs.readFileSync(CALLDATA_FILE, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean);
    return lines.map((calldata, i) => ({ rowIndex: i, calldata, submittedAt: null }));
  }
  const res = await fetch(sheetCsvUrl());
  const text = await res.text();
  if (!res.ok || text.trimStart().startsWith('<')) {
    throw new Error(`sheet fetch failed (HTTP ${res.status}) — is it shared "Anyone with the link can view", and SHEET_ID/SHEET_GID correct?`);
  }
  // gviz CSV: line 0 is the column labels; each remaining row is `"<timestamp>","<calldata>"` (neither
  // field contains a comma/quote).
  const lines = text.split('\n').map((s) => s.trim()).filter(Boolean).slice(1);
  return lines.map((l, i) => {
    const m = l.match(/^"(.*)","(.*)"$/);
    const submittedAt = m ? m[1] : null;
    const calldata = (m ? m[2] : l.replace(/^"(.*)"$/, '$1')).trim();
    return { rowIndex: i, calldata, submittedAt };
  });
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.NonceManager(new ethers.Wallet(RELAYER_PRIVATE_KEY, provider));
  const store = openStore(DB_FILE);

  // 1) Ingest ALL current sheet rows, keyed by content hash. INSERT OR IGNORE dedups rows already seen
  //    (any status), so re-reading the whole sheet each run is cheap and deleting/pruning old rows —
  //    or switching to a fresh sheet — is safe (positions no longer matter).
  const fresh = await readRows();
  for (const { rowIndex, calldata, submittedAt } of fresh) {
    store.insertPending(sha256(calldata.toLowerCase()), calldata, rowIndex, submittedAt);
  }
  console.log(`read ${fresh.length} sheet row(s)  |  ${store.summary()}`);

  // 2) Process every pending/retry row (retries survive restarts via the DB, unlike the old cursor).
  const todo = store.todo();
  console.log(`processing ${todo.length} pending/retry row(s)${DRY_RUN ? ' [dry-run]' : ''}`);
  for (const { calldata_hash, calldata, row_index, attempts } of todo) {
    const tag = row_index == null ? `claim ${calldata_hash.slice(0, 8)}` : `row ${row_index + 2}`; // +2: header + 1-based

    // Shape check — a malformed row is a permanent reject.
    if (!/^0x[0-9a-fA-F]+$/.test(calldata) || !calldata.toLowerCase().startsWith(CLAIM_SELECTOR) || calldata.length !== CLAIM_HEX_LEN) {
      console.warn(`${tag}: malformed calldata (need selector ${CLAIM_SELECTOR}, ${CLAIM_HEX_LEN} chars) — failed`);
      if (!DRY_RUN) store.markFailed(calldata_hash, 'malformed calldata');
      continue;
    }

    // 3) Simulate with eth_call (no gas). Classify the outcome:
    //    - a non-revert (RPC/network) error is transient infra → mark retry and STOP this run;
    //    - "No balance lodged" is retryable (the deposit may still arrive) up to RETRY_MAX attempts;
    //    - any other revert (bad proof, already-claimed/drained, invalid src/dst/domain) is permanent.
    try {
      await provider.call({ to: ESCROW_ADDRESS, data: calldata });
    } catch (e) {
      const reason = e.reason || e.shortMessage || e.message || '';
      if (e.code !== 'CALL_EXCEPTION') {
        console.error(`${tag}: simulate infra error (${reason}) — retry next run. Stopping.`);
        if (!DRY_RUN) store.markRetry(calldata_hash, reason);
        break;
      }
      if (/No balance lodged/i.test(reason) && attempts + 1 < RETRY_LIMIT) {
        console.warn(`${tag}: no balance lodged yet (attempt ${attempts + 1}/${RETRY_LIMIT}) — retry`);
        if (!DRY_RUN) store.markRetry(calldata_hash, reason);
      } else {
        console.warn(`${tag}: simulation reverted (${reason}) — failed`);
        if (!DRY_RUN) store.markFailed(calldata_hash, reason);
      }
      continue;
    }

    // 4) Submit. A transient submit error stops the run (retry next run); an on-chain revert is terminal.
    if (DRY_RUN) { console.log(`${tag}: [dry-run] would submit ${(calldata.length - 2) / 2} bytes to ${ESCROW_ADDRESS}`); continue; }
    try {
      const tx = await wallet.sendTransaction({ to: ESCROW_ADDRESS, data: calldata });
      const rcpt = await tx.wait();
      if (rcpt.status === 1) {
        store.markConfirmed(calldata_hash, tx.hash, rcpt.blockNumber);
        console.log(`${tag}: CONFIRMED ${tx.hash} @ block ${rcpt.blockNumber}`);
      } else {
        store.markFailed(calldata_hash, 'tx reverted on-chain');
        console.warn(`${tag}: tx ${tx.hash} reverted on-chain — failed`);
      }
    } catch (e) {
      console.error(`${tag}: submit error — ${e.shortMessage || e.message}. Retry next run. Stopping.`);
      store.markRetry(calldata_hash, e.shortMessage || e.message);
      break;
    }
  }

  console.log(`done${DRY_RUN ? ' [dry-run — no writes]' : ''}  |  ${store.summary()}`);
  store.close();
}

main().catch((e) => { console.error('fatal:', e.message || e); process.exit(1); });
