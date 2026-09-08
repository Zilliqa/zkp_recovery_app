# Claim relayer

Script that reads claim **calldata** users paste into a Google Form, checks each one against the
escrow, and submits the valid ones. The relayer key **only pays gas** — every proof binds its own
destination (`newAddr` is a public input), so this script **cannot redirect anyone's funds**; a
compromised relayer key can at worst stop relaying or waste its own gas.

> **Review and harden before production** (monitoring, key management, gas policy, retry/alerting).
> See "Assumptions" and "Not implemented yet" below.

## How it works
1. Reads the Form's **linked Google Sheet** (one row per submission) via a service account.
2. For each new row: **shape-checks** the calldata (hex, `claim()` selector `0xcf1c9461`, exact
   388-byte fixed length) → **simulates** `claim()` with `eth_call` (no gas spent) → and only then
   **submits** it.
3. Tracks a local **cursor** (rows processed) so it never re-submits; on-chain "already claimed" is the
   backstop, so a duplicate would just revert in simulation and be skipped.

The **`eth_call` simulation is the gate**: a claim whose source has no lodged balance reverts on the
escrow's `require(amount > 0, "No balance lodged")` (as do invalid/already-claimed proofs), so it is
skipped and **no tx is submitted, no gas spent**. ⚠ A revert is treated as final (skip + advance the
cursor) — so **users must deposit *before* pasting their calldata into the form**; a claim submitted
before its deposit lands is dropped and not retried. (A per-row retry model — see below — would remove
that constraint.)

## Setup
1. **Link the Form to a Sheet** — Form editor → Responses → *Link to Sheets*. Note the column header
   that holds the calldata (default expected: `Calldata`).
2. **Service account** — in Google Cloud: create a project, enable the **Google Sheets API**, create a
   **service account**, download its JSON key. **Share the responses Sheet** with the service
   account's email (`…@….iam.gserviceaccount.com`), Viewer access.
3. **Configure** — `cp .env.example .env` and fill it in (`GOOGLE_APPLICATION_CREDENTIALS` points at
   the JSON key; `SHEET_ID` is from the Sheet URL).
4. **Install & run:**
   ```bash
   npm install
   node relay.js --dry-run   # simulate + report every new row; sends nothing, cursor untouched
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
- **`e2e/`** — `forge test` over the **real** zq2 escrow (`escrow_v1.sol`) + integrated verifier (proof → `lodge` → `claim` → funds move), in-process, no node.
- **`e2e-anvil/`** — full path against a live anvil chain (id `32769`): deploy → impersonate-lodge → the **real `relay.js`** → payout assertion. See `e2e-anvil/README.md`.

## Assumptions
- **Append-only responses.** Form submissions only append, so a row's position is a stable cursor key.
- **Sequential submission.** Each tx is awaited before the next (simple, correct nonces). Fine for a
  daily batch; parallelize with explicit nonce management if volume grows.

## Not implemented yet (add for production)
- **Per-row retry state** (instead of the single linear cursor) so `balance == 0` rows can be retried
  later — removes the "deposit before submitting" constraint above.
- Alerting/metrics (submitted / skipped / reverted counts), structured logs.
- Relayer gas-balance monitoring and top-up.
- Optional: write a `status` column back to the Sheet per row (needs a read/write scope).
- Rate-limit / batch-size caps.

## Security notes
- `service-account.json` and `.env` (with `RELAYER_PRIVATE_KEY`) are secrets — git-ignored here; store
  them securely. The relayer key has **no privilege over the escrow** (a system contract, upgradeable
  only by `address(0)`) — it only pays gas — so fund it with just what relaying needs.
- Calldata is **public data** (a proof + public inputs) — nothing secret transits the form.
