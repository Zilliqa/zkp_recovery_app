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

// gviz JSON of a LINK-READABLE sheet (share = "Anyone with the link can view"), no auth: read the
// timestamp (column A) + calldata, only rows at/after the watermark (a datetime). We use JSON — not CSV
// — because it encodes the Form timestamp unambiguously as `Date(y,m0,d,h,mi,s)`, sidestepping the
// sheet's locale display format (M/D/YYYY vs D/M/YYYY). `where A >= …` is a real datetime comparison.
const sheetJsonUrl = (watermark) => {
  const where = watermark ? ` where A >= datetime '${watermark}'` : '';
  const tq = `select A, ${CALLDATA_COL}${where} order by A`;
  return `https://docs.google.com/spreadsheets/d/${SHEET_ID}/gviz/tq?tqx=out:json&gid=${SHEET_GID}&tq=${encodeURIComponent(tq)}`;
};

const pad2 = (n) => String(n).padStart(2, '0');
// "Date(2026,8,8,8,34,22)" (month is 0-indexed) -> "2026-09-08 08:34:22" (sheet timezone, sortable).
const gvizDateToIso = (v) => {
  const m = /^Date\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)/.exec(v || '');
  if (!m) return null;
  const [y, mo, d, h, mi, s] = m.slice(1).map(Number);
  return `${y}-${pad2(mo + 1)}-${pad2(d)} ${pad2(h)}:${pad2(mi)}:${pad2(s)}`;
};

// --- Read rows at/after `watermark`: timestamp (column A) + calldata ---
// From a local file (e2e/local testing) if CALLDATA_FILE is set, else the Google Sheet's public gviz JSON.
async function readRows(watermark) {
  if (CALLDATA_FILE) {
    // Testing source: one 0x-hex claim() calldata per non-empty line, in submission order (no timestamp).
    const lines = fs.readFileSync(CALLDATA_FILE, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean);
    return lines.map((calldata) => ({ calldata, submittedAt: null }));
  }
  const res = await fetch(sheetJsonUrl(watermark));
  const text = await res.text();
  const wrap = /setResponse\((.*)\);?\s*$/s.exec(text); // strip google.visualization.Query.setResponse(…)
  if (!res.ok || !wrap) {
    throw new Error(`sheet fetch failed (HTTP ${res.status}) — is it shared "Anyone with the link can view", and SHEET_ID/SHEET_GID correct?`);
  }
  const body = JSON.parse(wrap[1]);
  if (body.status === 'error') throw new Error(`gviz query error: ${JSON.stringify(body.errors)}`);
  return (body.table?.rows || [])
    .map((r) => ({ submittedAt: gvizDateToIso(r.c?.[0]?.v), calldata: (r.c?.[1]?.v || '').trim() }))
    .filter((x) => x.calldata);
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.NonceManager(new ethers.Wallet(RELAYER_PRIVATE_KEY, provider));
  const store = openStore(DB_FILE);

  // 1) Ingest new rows: read only rows at/after the stored timestamp watermark, keyed by content hash.
  //    Watermark-based reads scale (O(new)) and survive pruning/reordering (it's a time, not a position);
  //    INSERT OR IGNORE dedups, so switching to a fresh sheet is also safe.
  const watermark = store.getWatermark();
  const fresh = await readRows(watermark);
  let maxTs = watermark;
  for (const { calldata, submittedAt } of fresh) {
    store.insertPending(sha256(calldata.toLowerCase()), calldata, submittedAt);
    if (submittedAt && (!maxTs || submittedAt > maxTs)) maxTs = submittedAt;
  }
  // Advance the watermark to the newest timestamp read — rows are safely in the DB now, and retries
  // happen via `todo`, not by re-reading the sheet. Next run's `>=` re-reads only same-second rows (deduped).
  if (!DRY_RUN && maxTs && maxTs !== watermark) store.setWatermark(maxTs);
  console.log(`read ${fresh.length} row(s) since ${watermark ?? 'start'}  |  ${store.summary()}`);

  // 2) Process every pending/retry row (retries survive restarts via the DB, unlike the old cursor).
  const todo = store.todo();
  console.log(`processing ${todo.length} pending/retry row(s)${DRY_RUN ? ' [dry-run]' : ''}`);
  for (const { calldata_hash, calldata, submitted_at, attempts } of todo) {
    const tag = submitted_at ? `[${submitted_at}]` : `claim ${calldata_hash.slice(0, 8)}`;

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
