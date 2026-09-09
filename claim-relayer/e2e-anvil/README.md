# Anvil e2e for the claim relayer

Exercises the **full relayer path against a live JSON-RPC node** — deploy escrow → seed a balance for a
legacy source address → feed the claim calldata to the real `relay.js` → confirm the funds land at the
proof-bound destination. This complements `../e2e-forge/` (which validates the escrow + verifier *logic*
in-process with `forge test` but never runs `relay.js`).

## Why anvil, and why chain id 32769

The escrow enforces `pubSignals[2] == block.chainid`, and the Flutter app **hard-codes** the proof
`domain` per build: **`32769` (release / zq2-mainnet)** or `33101` (debug / zq2-testnet). So the local
node's chain id must equal the domain baked into the proof you're testing:

| target the proof was built for | run anvil with |
|---|---|
| release app / zq2-mainnet | `anvil --chain-id 32769` ← this harness |
| debug app / zq2-testnet | `anvil --chain-id 33101` |
| zq2-devnet (33469) | needs a custom app build with `domain=33469`; no stock build matches |

Anvil is also the only place we can **credit the legacy (SHA-256) source address**: `lodge()` credits
`msg.sender`, and on a real EVM chain `msg.sender` is Keccak-derived, so we impersonate the legacy
address (`anvil_impersonateAccount`) — the "impossible on a real chain" step. (In production the escrow
balance is seeded by zq2 itself, not by an EVM `lodge()`.)

## Prerequisites

- **Foundry** (`anvil`, `forge`, `cast`) and **Node 18+**.
- Relayer deps: from `..` (the `claim-relayer/` root) run `npm install`.
- The **production proving key**. `../e2e-forge/claim.json` is committed, so you can run this harness as-is.
  To regenerate the proof (e.g. a different destination), download `circuit_final.zkey` into
  `../../groth16-prover-min/` (or set `ZKEY=/path/to/final.zkey`) and run `node ../e2e-forge/gen_calldata.cjs`.

The committed proof uses the public all-zero BIP-39 test vector: source
`0xb413df42a4e2d5236fe1b914a21c354eb86f133c`, destination `0x00112233445566778899aabbccddeeff00112233`,
`domain=32769`, `isHardened=1`.

## Run it

```bash
# terminal A — a mainnet-domain chain
anvil --chain-id 32769

# terminal B — from claim-relayer/e2e-anvil/
./run.sh
```

`run.sh` compiles the escrow, deploys it, lodges 1 ZIL for the source address (impersonated), runs the
**real `relay.js`** against anvil, then asserts the payout. Expected tail:

```
✅ e2e PASS — relayer claimed and funds moved to the proof-bound destination
```

### Step by step (what `run.sh` does)

```bash
( cd ../e2e-forge && forge build )                       # compile escrow_v1.sol (+ verifier.sol)
node deploy_and_lodge.js                            # deploy, impersonate-lodge -> writes .escrow_addr + calldata.txt
ESCROW_ADDRESS=$(cat .escrow_addr) \
RPC_URL=http://127.0.0.1:8545 \
RELAYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
CALLDATA_FILE=./calldata.txt DB_FILE=$(mktemp) \
  node ../relay.js                                 # the real relayer: shape check -> simulate -> submit
node verify_payout.js                              # balances[src]==0 and balance(dst)==lodged
```

`CALLDATA_FILE` is a testing-only source in `relay.js`: one `0x` calldata per line, run through the
**same** shape/simulate/submit path as the Sheet. Everything but the row source is identical.

## Testing the REAL Google Form + Sheet path

`sheet_demo.js` drives **3 committed example claims** (`examples.json` — accounts 0/1/2 of the public
test seed, paying 1/2/3 ZIL to distinct destinations) through a real **link-readable** sheet:

1. **Share** your responses sheet "Anyone with the link can view" (see `../README.md`).
2. **Deploy + lodge** for all 3 example sources — prints the 3 calldata and the escrow address:
   ```bash
   ( cd ../e2e-forge && forge build )
   node sheet_demo.js
   ```
3. **Paste** each printed calldata into the Google Form (one submission each).
4. **Run the relayer** against your sheet + the printed escrow:
   ```bash
   RPC_URL=http://127.0.0.1:8545 ESCROW_ADDRESS=<from step 2> \
   RELAYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
   SHEET_ID=<id> SHEET_GID=<gid> CALLDATA_COL=B DB_FILE=$(mktemp) node ../relay.js
   ```
5. **Verify** all 3 payouts:
   ```bash
   node sheet_demo.js --verify
   ```

Regenerate the examples (different destinations/amounts) with a matching zkey:
`ZKEY=/path/to/final.zkey node gen_examples.cjs`.

## Notes

- The relayer key only pays gas; every proof binds its own destination (`newAddr` is a public input),
  so the relayer cannot redirect funds.
- Re-running is safe without restarting anvil: each run deploys a fresh escrow, and the payout check
  compares the destination's balance **change** (snapshotted before the claim), not its absolute value —
  so an accumulating `newAddr` balance (1 → 2 → 3 ZIL across runs) still passes.
