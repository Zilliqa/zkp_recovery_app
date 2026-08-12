# Zilliqa seed-ownership zk-proof runner — PLONK, minimal circuit

The **PLONK** counterpart of `../groth16-prover-min`. **Identical circuit, inputs, and command** —
it differs only in the proof system. PLONK's advantage is a **universal setup (no per-circuit
ceremony)**; the costs are a bigger key and heavier proving.

> Recommendation: for end users, prefer the **Groth16** minimal runner (`../groth16-prover-min`):
> ~15 s, ~7 GB, 247 MB key. This PLONK variant is provided for the "no-ceremony" case. The
> minimal circuit is what makes PLONK viable at all — on the full circuit it needed ~1 hr / ~50 GB.

## What it proves
Same as `groth16-prover-min`: the `m/44'/313'/n'/0'` parent node (private, **binary-constrained**),
final hardened step `0'` in-circuit → address `== old`, bound to `newAddr` + `domain`. Public
inputs `[old, new, domain]`. The seed → parent-node derivation and account-index auto-scan happen
off-circuit in `prepare.js`/`prove-secure.js`.

## Use it (same command as every other runner)
```bash
./run-proof-secure.sh <oldAddr> <newAddr> <domain>          # hardened (hidden mnemonic prompt)
./run-proof.sh "<mnemonic>" <oldAddr> <newAddr> <domain>    # quick (throwaway seeds only)
```

## The proving key (not in git — too big even for Releases)
`circuit_final.zkey` (**3.7 GB**) exceeds **both** GitHub's 100 MB repo limit and its 2 GB
Release-asset limit, so it is hosted in an **external bucket (GCS)**. Download it into this folder:
```
curl -L -o circuit_final.zkey https://storage.googleapis.com/bkt-p-zkproof-files-001/plonk-runner-min/circuit_final.zkey
# verify against the published checksum before use:  sha256sum circuit_final.zkey
```
No secrets in the key. `vk.json` + `verifier.sol` are in the repo.

## Requirements
- Node.js (first run installs `@scure/*`, `bip39`, `snarkjs` 0.7.6).
- **PLONK proving is heavy: ~20 min, ~15 GB RAM.** The runner sets a large Node heap
  (`--max-old-space-size=16384`). Disk: 3.7 GB (key) + deps. Run it alone (don't run other
  memory-heavy jobs at the same time).

## On-chain
`verifier.sol` is the PLONK verifier: `verifyProof(uint256[24] _proof, uint256[3] _pubSignals)`,
pubSignals = `[old, new, domain]`. `print_submit.js` emits matching calldata.

## Files
- `run-proof-secure.sh` / `prove-secure.js`, `run-proof.sh` / `prepare.js` — runners (same as the Groth16 min variant, `plonk.*` proving).
- `circuit.circom` + `bip32lib.circom`, `circuit_js/` — the minimal circuit (same one; PLONK just uses it differently).
- `vk.json`, `verifier.sol`, `print_submit.js`.
