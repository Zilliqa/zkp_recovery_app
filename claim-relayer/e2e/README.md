# Escrow claim — end-to-end test

Reproducible on-chain test of the fund-reclaim path: a **real Groth16 proof** → `lodge()` (deposit
credited to the legacy source address) → `claim()` verifies the proof and **moves the funds to the
`newAddr` baked into the proof**. This is the on-chain half of the [`claim-relayer`](../)
flow (the relayer just submits the same `claim()` calldata).

It runs against the **real zq2 escrow** (`src/escrow_v1.sol`) and its **integrated verifier**
(`src/verifier.sol`), deployed behind an **ERC1967 proxy with empty init data** — mirroring zq2's
production deployment (implementation + proxy, `initialize()` not called at deploy).

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
- asserts the funds land at `newAddr` and the source balance is zeroed,
- replay check: a second claim on the zeroed balance **reverts** (`require(amount > 0)`) and moves nothing.

## Files
- `src/escrow_v1.sol` — the **real** zq2 escrow (`EscrowInit`: UUPS-upgradeable, ERC-7201 storage,
  integrated `internal verifyProof`, guards `amount>0` / `src!=0` / `dst!=0`).
- `src/verifier.sol` — the **real** integrated `Groth16Verifier` (matches the ceremony `final.zkey` and
  `claim.json`).
- `vendor/` — the minimal OpenZeppelin closure needed to compile `escrow_v1.sol` (`UUPSUpgradeable`) and
  deploy it behind a proxy (`ERC1967Proxy`), plus their transitive imports.
- `test/Escrow.t.sol` — the e2e test (self-contained cheatcode interface; no forge-std dependency).
- `claim.json` — a real production-key proof + its `claim()` calldata (so the test needs no proving).
- `gen_calldata.js` — regenerate `claim.json` (only if you change the circuit/key).

## Provenance (keep in sync with zq2)
`src/escrow_v1.sol` and `src/verifier.sol` are **byte-identical copies** of
`zilliqa/src/contracts/escrow/{escrow_v1.sol,verifier.sol}` from **zq2 `release/v0.21.9`**. `vendor/` is
the minimal import closure from **OpenZeppelin 5.1.0** (`openzeppelin-contracts` @ `653963be`,
`openzeppelin-contracts-upgradeable` @ `94c7b7c8` — the commits zq2 pins). Compiled with **solc 0.8.28**
(OZ 5.1's UUPSUpgradeable needs `^0.8.22`). Re-copy these if zq2's escrow changes.

## Regenerate `claim.json`
Needs the prover's deps + wasm (`../../groth16-prover-min`) and a matching zkey (not in git):
```bash
ZKEY=/path/to/final.zkey VK=/path/to/vk.json node gen_calldata.js
```
If you regenerate with a different key, also refresh the VK constants in `src/verifier.sol` (re-copy it
from the escrow built against that key), so the committed pair stays consistent.

## Notes
- `newAddr` and `domain` in the proof are set at prove time; the committed proof uses `domain=32769`
  and a fixed test `newAddr` — see `gen_calldata.js`.
- Deployment mirrors production: implementation + `ERC1967Proxy(impl, "")` (empty init data, so
  `initialize()` is not called), and all calls go through the proxy via `delegatecall`. What's still
  not exercised here is a live UUPS *upgrade* (`upgradeToAndCall`) and the fixed on-chain proxy address
  — those belong to the zq2/devnet deployment, not the relayer.
