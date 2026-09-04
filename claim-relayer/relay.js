#!/usr/bin/env node
// Claim relayer — SKETCH / starting point (review & harden before production).
//
// Once a day: read new claim entries from the Google Form's linked Sheet, simulate each against the
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
import { google } from 'googleapis';
import { ethers } from 'ethers';

const {
  RPC_URL,
  ESCROW_ADDRESS,
  RELAYER_PRIVATE_KEY,
  SHEET_ID,
  SHEET_RANGE = 'Form Responses 1!A:Z',
  CALLDATA_COLUMN = 'Calldata',
  CURSOR_FILE = './.cursor',
  // GOOGLE_APPLICATION_CREDENTIALS = path to the service-account JSON key (read by google-auth)
} = process.env;

for (const [k, v] of Object.entries({ RPC_URL, ESCROW_ADDRESS, RELAYER_PRIVATE_KEY, SHEET_ID })) {
  if (!v) { console.error(`Missing required env: ${k}`); process.exit(1); }
}

const DRY_RUN = process.argv.includes('--dry-run') || process.env.DRY_RUN === '1';
const CLAIM_SELECTOR = '0xcf1c9461'; // claim(uint256[2],uint256[2][2],uint256[2],uint256[4])
if (DRY_RUN) console.log('[dry-run] will simulate and report only — no transactions sent, cursor not advanced');

// --- Read response rows from the Form's linked Sheet (service-account, read-only) ---
async function readRows() {
  const auth = new google.auth.GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/spreadsheets.readonly'], // uses GOOGLE_APPLICATION_CREDENTIALS
  });
  const sheets = google.sheets({ version: 'v4', auth });
  const res = await sheets.spreadsheets.values.get({ spreadsheetId: SHEET_ID, range: SHEET_RANGE });
  const [header, ...rows] = res.data.values || [];
  if (!header) return [];
  const col = header.indexOf(CALLDATA_COLUMN);
  if (col < 0) throw new Error(`Column "${CALLDATA_COLUMN}" not in header: ${header.join(', ')}`);
  // Form responses only ever append, so a row's position is stable → index is a safe cursor key.
  return rows.map((r, i) => ({ index: i, calldata: (r[col] || '').trim() }));
}

// --- Idempotency: how many rows we've already handled (persisted locally) ---
const readCursor = () => { try { return parseInt(fs.readFileSync(CURSOR_FILE, 'utf8'), 10) || 0; } catch { return 0; } };
const writeCursor = (n) => fs.writeFileSync(CURSOR_FILE, String(n));

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(RELAYER_PRIVATE_KEY, provider);

  const rows = await readRows();
  const start = readCursor();
  const fresh = rows.filter((r) => r.index >= start);
  console.log(`rows=${rows.length} alreadyProcessed=${start} new=${fresh.length}`);

  let cursor = start;
  for (const { index, calldata } of fresh) {
    const tag = `row ${index + 2}`; // +2: 1 header row, and sheets are 1-based

    // Shape check: must be hex AND start with the claim() selector — rejects pasted junk / wrong data.
    if (!/^0x[0-9a-fA-F]+$/.test(calldata) || !calldata.toLowerCase().startsWith(CLAIM_SELECTOR)) {
      console.warn(`${tag}: not a claim() calldata (must start with ${CLAIM_SELECTOR}), skipping`);
      cursor = index + 1;
      continue;
    }

    // 1) Simulate. Catches invalid proof, already-claimed, missing deposit, etc. — WITHOUT spending gas.
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
