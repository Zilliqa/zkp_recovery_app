# Claim relayer (sketch)

Daily job that reads claim **calldata** users paste into a Google Form, checks each one against the
escrow, and submits the valid ones. The relayer key **only pays gas** — every proof binds its own
destination (`newAddr` is a public input), so this script **cannot redirect anyone's funds**; a
compromised relayer key can at worst stop relaying or waste its own gas.

> **Status: sketch.** Review and harden before production (monitoring, key management, gas policy,
> retry/alerting). See "Assumptions" below.

## How it works
1. Reads the Form's **linked Google Sheet** (one row per submission) via a service account.
2. For each new row: shape-checks the calldata, **simulates** `claim()` with `eth_call` (catches
   invalid proof / already-claimed / missing deposit — no gas spent), and only then **submits** it.
3. Tracks a local **cursor** (rows processed) so it never re-submits; on-chain "already claimed" is the
   backstop, so a duplicate would just revert in simulation and be skipped.

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

## Calldata format (confirmed)
The form field is the **complete `0x…` transaction data** for the escrow's `claim()` — verified against
the Flutter app (`proof_service.dart` `encodeCallData`): 4-byte selector `0xcf1c9461`
(`claim(uint256[2],uint256[2][2],uint256[2],uint256[4])`) + ABI-encoded proof (a,b,c) + 4 public inputs.
The script checks the selector and sends the bytes verbatim as `tx.data` — no ABI/Interface needed.

## Other assumptions
- **Append-only responses.** Form submissions only append, so a row's position is a stable cursor key.
- **Sequential submission.** Each tx is awaited before the next (simple, correct nonces). Fine for a
  daily batch; parallelize with explicit nonce management if volume grows.

## Not in this sketch (add for production)
- Alerting/metrics (submitted / skipped / reverted counts), structured logs.
- Relayer gas-balance monitoring and top-up.
- Optional: write a `status` column back to the Sheet per row (needs a read/write scope).
- Rate-limit / batch-size caps and a dry-run mode.

## Security notes
- `service-account.json` and `.env` (with `RELAYER_PRIVATE_KEY`) are secrets — git-ignored here; store
  them securely. Keep the relayer key **separate** from any escrow-admin key.
- Calldata is **public data** (a proof + public inputs) — nothing secret transits the form.
