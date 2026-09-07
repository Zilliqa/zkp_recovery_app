# Escrow claim — end-to-end test

Reproducible on-chain test of the fund-reclaim path: a **real Groth16 proof** → `lodge()` (deposit
credited to the legacy source address) → `claim()` verifies the proof and **moves the funds to the
`newAddr` baked into the proof**. This is the on-chain half of the [`claim-relayer`](../claim-relayer/)
flow (the relayer just submits the same `claim()` calldata).

## Run it
```bash
forge test -vv
```
It's **standalone** — no proving or chain daemon needed. It reads the committed **`claim.json`** (a real
proof + the exact app `claim()` calldata, from the production ceremony key) and runs everything in
forge's in-process EVM:
- `vm.chainId(32769)` (the escrow requires `pubSignals[2] == block.chainid`),
- impersonates the legacy source address and calls the real `lodge{value}()`,
- submits the calldata verbatim to `claim()`,
- asserts the funds land at `newAddr` and the source balance is zeroed (+ a replay check).

## Files
- `src/verifier.sol` — the production `Groth16Verifier` (matches the ceremony `final.zkey` and `claim.json`).
- `src/Escrow.sol` — faithful minimal escrow: `lodge`/`claim`/`balances` copied from zq2 `escrow_v1.sol`,
  **minus** the UUPS/proxy machinery (deployment plumbing, covered on devnet). `claim()` calls the stock
  verifier via an external self-call (`this.verifyProof`) so its assembly `return` yields a correct bool;
  the real escrow uses the integrated `internal verifyProof`. The verify/payout logic is identical.
- `test/Escrow.t.sol` — the e2e test (self-contained cheatcode interface; no forge-std dependency).
- `claim.json` — a real production-key proof + its `claim()` calldata (so the test needs no proving).
- `gen_calldata.js` — regenerate `claim.json` (only if you change the circuit/key).

## Regenerate `claim.json`
Needs the prover's deps + wasm (`../groth16-prover-min`) and a matching zkey (not in git):
```bash
ZKEY=/path/to/final.zkey VK=/path/to/vk.json node gen_calldata.js
```
If you regenerate with a different key, also refresh `src/verifier.sol` from that key's
`snarkjs zkey export solidityverifier`, so the committed pair stays consistent.

## Notes
- `newAddr` and `domain` in the proof are set at prove time; the committed proof uses `domain=32769`
  and a fixed test `newAddr` — see `gen_calldata.js`.
- This validates the escrow claim logic + proof verification; the UUPS proxy deployment is exercised on
  the Zilliqa devnet, not here.
