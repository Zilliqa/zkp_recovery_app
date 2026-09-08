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
import { ethers } from 'ethers';

const {
  RPC_URL,
  ESCROW_ADDRESS,
  RELAYER_PRIVATE_KEY,
  SHEET_ID,                       // spreadsheet id, from its URL: /spreadsheets/d/<SHEET_ID>/edit
  SHEET_GID = '0',                // the responses tab's gid (the #gid=… in the URL)
  CALLDATA_COL = 'B',             // column letter holding the calldata (Forms: Timestamp=A, 1st question=B)
  CURSOR_FILE = './.cursor',
  CALLDATA_FILE,                  // e2e/local testing ONLY: read calldata from this file instead of the Sheet
} = process.env;

// SHEET_ID is required only for the real Google-Sheet source; CALLDATA_FILE mode doesn't need it.
const required = { RPC_URL, ESCROW_ADDRESS, RELAYER_PRIVATE_KEY, ...(CALLDATA_FILE ? {} : { SHEET_ID }) };
for (const [k, v] of Object.entries(required)) {
  if (!v) { console.error(`Missing required env: ${k}`); process.exit(1); }
}

const DRY_RUN = process.argv.includes('--dry-run') || process.env.DRY_RUN === '1';
const CLAIM_SELECTOR = '0xcf1c9461'; // claim(uint256[2],uint256[2][2],uint256[2],uint256[4])
const CLAIM_HEX_LEN = 778;           // fixed size: '0x' + 4-byte selector + 12×32-byte words = 388 bytes
if (DRY_RUN) console.log('[dry-run] will simulate and report only — no transactions sent, cursor not advanced');

// Public CSV endpoint for a LINK-READABLE sheet (share = "Anyone with the link can view"): the gviz
// query reads only the calldata column, only from the cursor row onward (offset) → O(new rows), no auth.
const sheetCsvUrl = (start) =>
  `https://docs.google.com/spreadsheets/d/${SHEET_ID}/gviz/tq?tqx=out:csv&gid=${SHEET_GID}` +
  `&tq=${encodeURIComponent(`select ${CALLDATA_COL} offset ${start}`)}`;

// --- Read only the NEW rows (index >= start), and only the calldata column ---
// From a local file (e2e/local testing) if CALLDATA_FILE is set, else the Google Sheet's public CSV.
async function readRows(start) {
  if (CALLDATA_FILE) {
    // Testing source: one 0x-hex claim() calldata per non-empty line, in submission order. Same rows
    // shape as the Sheet path, so every downstream check (shape, simulate, submit) is identical.
    const lines = fs.readFileSync(CALLDATA_FILE, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean);
    return lines.slice(start).map((calldata, i) => ({ index: start + i, calldata }));
  }
  const res = await fetch(sheetCsvUrl(start));
  const text = await res.text();
  if (!res.ok || text.trimStart().startsWith('<')) {
    throw new Error(`sheet fetch failed (HTTP ${res.status}) — is it shared "Anyone with the link can view", and SHEET_ID/SHEET_GID correct?`);
  }
  // gviz CSV: line 0 is the column label; the rest are the calldata values (each quoted). `offset start`
  // already dropped the processed rows, so these all map to index >= start (responses are append-only).
  const lines = text.split('\n').map((s) => s.trim()).filter(Boolean).slice(1);
  return lines.map((l, i) => ({ index: start + i, calldata: l.replace(/^"(.*)"$/, '$1').trim() }));
}

// --- Idempotency: how many rows we've already handled (persisted locally) ---
const readCursor = () => { try { return parseInt(fs.readFileSync(CURSOR_FILE, 'utf8'), 10) || 0; } catch { return 0; } };
const writeCursor = (n) => fs.writeFileSync(CURSOR_FILE, String(n));

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(RELAYER_PRIVATE_KEY, provider);

  const start = readCursor();
  const fresh = await readRows(start); // already only the unprocessed rows
  console.log(`alreadyProcessed=${start} new=${fresh.length}`);

  let cursor = start;
  for (const { index, calldata } of fresh) {
    const tag = `row ${index + 2}`; // +2: 1 header row, and sheets are 1-based

    // Shape check: hex, correct selector, AND the exact fixed length (claim() args are all fixed-size).
    if (!/^0x[0-9a-fA-F]+$/.test(calldata) || !calldata.toLowerCase().startsWith(CLAIM_SELECTOR) || calldata.length !== CLAIM_HEX_LEN) {
      console.warn(`${tag}: not a well-formed claim() calldata (selector ${CLAIM_SELECTOR}, exactly ${CLAIM_HEX_LEN} chars), skipping`);
      cursor = index + 1;
      continue;
    }

    // 1) Simulate. The gate: catches invalid proof, already-claimed, and no-balance-lodged (the escrow
    //    reverts on amount==0) — WITHOUT spending gas. NOTE: a revert is treated as final (skip + advance
    //    the cursor), so a claim pasted BEFORE its deposit lands is dropped and not retried; users must
    //    deposit first (see README).
    try {
      await provider.call({ to: ESCROW_ADDRESS, data: calldata });
    } catch (e) {
      // A revert here is a permanent "no" for this exact calldata → skip and never retry it.
      console.warn(`${tag}: simulation reverted (${e.shortMessage || e.reason || e.message}) — skipping`);
      cursor = index + 1;
      continue;
    }

    // 2) Submit (or, in --dry-run, just report). Sequential → simple, correct nonce handling.
    if (DRY_RUN) {
      console.log(`${tag}: [dry-run] simulation passed — would submit ${(calldata.length - 2) / 2} bytes to ${ESCROW_ADDRESS}`);
      continue; // do NOT advance cursor in dry-run (see the guarded writeCursor below)
    }
    try {
      const txReq = { to: ESCROW_ADDRESS, data: calldata };
      // Optional: const gas = await provider.estimateGas({ ...txReq, from: wallet.address });
      const tx = await wallet.sendTransaction(txReq);
      console.log(`${tag}: submitted ${tx.hash}`);
      const rcpt = await tx.wait();
      console.log(`${tag}: ${rcpt.status === 1 ? 'CONFIRMED' : 'FAILED'} @ block ${rcpt.blockNumber}`);
      cursor = index + 1; // advance only after a confirmed (or definitively failed) submission
    } catch (e) {
      // Transient (RPC/nonce/timeout): stop WITHOUT advancing so this row is retried next run.
      console.error(`${tag}: submit error — ${e.shortMessage || e.message}. Stopping; will retry next run.`);
      break;
    }
  }

  if (DRY_RUN) {
    console.log('[dry-run] done — cursor NOT persisted; re-run without --dry-run to submit');
  } else {
    writeCursor(cursor);
    console.log(`cursor -> ${cursor}`);
  }
}

main().catch((e) => { console.error('fatal:', e.message || e); process.exit(1); });
