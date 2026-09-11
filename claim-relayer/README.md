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
   **retry** rows that aren't claimable yet. Rows are **keyed by a hash of the submission**
   (`timestamp + calldata`), so each Form submission is tracked on its own — a proof re-submitted after a
   fresh `lodge()` is a new row and **gets claimed again** (the escrow has no per-proof nonce, so a proof
   stays claimable while `balances[src] > 0`) — while **deleting / pruning / reordering** rows, or a fresh
   sheet, stays safe (positions don't matter).

The **`eth_call` simulation is the gate**: an invalid proof (bad / wrong-domain / invalid src·dst)
reverts and is marked **`failed`** (never retried). A claim whose deposit hasn't landed reverts on
`require(amount > 0, "No balance lodged")` and is marked **`retry`** — re-attempted next run up to
`RETRY_MAX` times — so a claim pasted **before** its deposit is no longer lost. Nothing is submitted and
no gas is spent until simulation passes.

> Caveat: `No balance lodged` is ambiguous — *no deposit yet* (retry is right) vs *already drained* (a
> re-paste with nothing left to claim). Both retry up to `RETRY_MAX` before `failed`. Harmless (free
> `eth_call`s), and the retry window actually helps the top-up case — a re-paste that's currently empty
> but gets a fresh `lodge()` within the window is then claimed. Disambiguating the truly-terminal case
> would need the escrow's `Released` event.

A `failed` row tells you **where** it failed: a set `tx_hash`/`block` means a submitted tx **reverted
on-chain** (rare — state changed between simulate and submit; go inspect the tx), while a NULL `tx_hash`
means it was rejected in **simulation** and never submitted (`last_error` has the escrow's reason).

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
- **Submission-keyed + timestamp watermark.** Rows are keyed by a hash of `timestamp + calldata` and read
  incrementally from a stored timestamp watermark, so the sheet can be pruned / reordered / replaced
  without breaking tracking, each distinct submission is processed once (a proof re-pasted after a new
  `lodge()` is a new submission → re-claimed), and reads stay O(new) rather than whole-sheet. The
  watermark uses gviz's unambiguous `Date(y,m,d,…)` JSON encoding — not the sheet's locale display — so
  M/D/YYYY vs D/M/YYYY doesn't matter. (Assumes column A is the Form's datetime `Timestamp`.)
- **Single instance (enforced).** Run **one** relayer at a time — two would double-submit and clash
  nonces. A second instance detects the first via a PID lock file (`<DB_FILE>.lock`) and **exits cleanly**
  ("another relayer instance appears to be running") instead of crashing on `SQLITE_BUSY`; a stale lock
  from a crashed run is taken over automatically. (A `busy_timeout` also waits out a transient lock, e.g.
  an open `sqlite3` reader.) `--dry-run` is read-only and takes no lock. True multi-instance would still
  need a shared DB + row-level leasing.
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
