# Claim relayer

Script that reads claim **calldata** users paste into a Google Form, checks each one against the
escrow, and submits the valid ones. The relayer key **only pays gas** — every proof binds its own
destination (`newAddr` is a public input), so this script **cannot redirect anyone's funds**; a
compromised relayer key can at worst stop relaying or waste its own gas.

> **Review and harden before production** (monitoring, key management, gas policy, alerting).
> See "Assumptions" and "Security notes" below.

## How it works
1. Reads **new rows** of the Form's **linked Google Sheet** (those at/after a stored **timestamp
   watermark**) via its public **gviz JSON** endpoint — the sheet is shared "Anyone with the link can
   view", so **no credentials/GCP project are needed**, and each run only fetches the recent tail (O(new)).
2. For each row: **shape-checks** the calldata (hex, `claim()` selector `0xcf1c9461`, exact 388-byte
   fixed length) → **simulates** `claim()` with `eth_call` (no gas spent) → and only then **submits** it.
3. Records each row's status in a local **SQLite DB** (`DB_FILE`, table `sheet_rows`) — `pending` /
   `confirmed` / `failed` / `retry` — so it never re-submits, survives restarts/crashes, and can
   **retry** rows that aren't claimable yet. Rows are **keyed by a hash of the calldata** (content), so
   duplicate submissions dedup and **deleting / pruning / reordering** sheet rows — or pointing at a
   fresh sheet — is safe (positions don't matter).

The **`eth_call` simulation is the gate**: an invalid proof (bad / wrong-domain / invalid src·dst)
reverts and is marked **`failed`** (never retried). A claim whose deposit hasn't landed reverts on
`require(amount > 0, "No balance lodged")` and is marked **`retry`** — re-attempted next run up to
`RETRY_MAX` times — so a claim pasted **before** its deposit is no longer lost. Nothing is submitted and
no gas is spent until simulation passes.

> Caveat: an *already-claimed* row also reverts with `No balance lodged` (its balance was drained), so it
> too is retried up to `RETRY_MAX` before being marked `failed`. Harmless (each retry is a free
> `eth_call`), but a richer store could disambiguate via the escrow's `Released` event.

## Setup
1. **Link the Form to a Sheet** — Form editor → Responses → *Link to Sheets*. The relayer expects the
   fixed Form layout: column `A` = `Timestamp`, column `B` = the calldata question.
2. **Make it link-readable** — Share → General access → **"Anyone with the link" = Viewer**. No GCP
   project or service account is needed; the sheet holds only public calldata (see Security notes).
3. **Configure** — `cp .env.example .env` and set `SHEET_ID` + `SHEET_GID` (both in the Sheet URL:
   `/spreadsheets/d/<SHEET_ID>/edit#gid=<SHEET_GID>`).
4. **Install & run** (needs **Node 22+** — the state DB uses the built-in `node:sqlite`):
   ```bash
   npm install
   node relay.js --dry-run   # ingest + simulate + report; sends nothing, no status writes
   node relay.js             # real batch: submit the rows that pass simulation
   ```
5. **Schedule** — run daily via cron, e.g.:
   ```
   0 6 * * *  cd /path/to/claim-relayer && /usr/bin/node relay.js >> relay.log 2>&1
   ```

## Calldata format
The form field is the **complete `0x…` transaction data** for the escrow's `claim()`: 4-byte selector
`0xcf1c9461` (`claim(uint256[2],uint256[2][2],uint256[2],uint256[4])`) + ABI-encoded proof (a,b,c) +
4 public inputs — **388 bytes**. The relayer checks the selector and exact length, then sends the bytes
verbatim as `tx.data` (no ABI/Interface needed).

## Testing
- **`e2e-forge/`** — `forge test` over the **real** zq2 escrow (`escrow_v1.sol`) + integrated verifier (proof → `lodge` → `claim` → funds move), in-process, no node.
- **`e2e-anvil/`** — full path against a live anvil chain (id `32769`): deploy → impersonate-lodge → the **real `relay.js`** → payout assertion. See `e2e-anvil/README.md`.

## Assumptions
- **Fixed sheet layout.** The relayer reads the Form's linked responses tab with column **`A` = the Form
  `Timestamp`** (a datetime) and column **`B` = the calldata** question — the default single-question Form
  layout. It queries exactly `A, B`, so extra columns (e.g. notes in `C`) are ignored, but the calldata
  must stay in `B` (don't insert columns to its left).
- **Content-keyed + timestamp watermark.** Rows are deduped by calldata hash and read incrementally from
  a stored timestamp watermark, so the sheet can be pruned / reordered / replaced without breaking
  tracking, each unique claim is processed once, and reads stay O(new) rather than whole-sheet. The
  watermark uses gviz's unambiguous `Date(y,m,d,…)` JSON encoding — not the sheet's locale display — so
  M/D/YYYY vs D/M/YYYY doesn't matter. (Assumes column A is the Form's datetime `Timestamp`.)
- **Single instance.** The SQLite DB has no cross-process lock, so run **one** relayer at a time (two
  concurrent runs could grab the same row). Multi-instance would need a shared DB + row locking.
- **Sequential submission.** Each tx is awaited before the next (simple, correct nonces via `NonceManager`).
  Fine for a batch; parallelize with managed nonces / multiple keys if volume grows.

## Security notes
- `.env` (with `RELAYER_PRIVATE_KEY`) is the only secret — git-ignored here; store it securely. The
  relayer key has **no privilege over the escrow** (a system contract, upgradeable only by `address(0)`)
  — it only pays gas — so fund it with just what relaying needs.
- The **sheet is public-read**, which is fine: calldata is **public data** (a proof + public inputs)
  that ends up on-chain anyway, and writes still happen only through the Form (the public view is
  read-only, so entries can't be tampered). The relayer also re-simulates every row on-chain, so a
  garbage entry can't move funds — worst case a wasted `eth_call`.
