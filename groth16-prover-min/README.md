# Zilliqa seed-ownership zk-proof runner — Groth16, minimal circuit

Same purpose as the full-circuit Groth16 runner (prove your seed controls a compromised Zilliqa account, bound
to a safe destination + domain, without revealing the seed), but on the **minimal circuit**:
only the **final hardened BIP-32 step** (`…/0'`) is done in-circuit; the seed → `m/44'/313'/n'/0'`
parent node is derived **off-circuit**. That makes the circuit **~4.5× smaller** (427k vs 1.94M
constraints), so proving is ~15 s at ~7 GB with a **247 MB** key.

## What it proves
`parent node m/44'/313'/n'/0'  --(final hardened CKD 0')-->  key --secp256k1--> pubkey --SHA-256[-20:]--> address == <old>`, bound to `newAddr` + `domain`.
- **Private inputs:** the parent node's private key + chain code (256+256 bits), each **binary-constrained**.
- **Public inputs:** `[expectedAddr(old), newAddr, domain]`.
- **Off-circuit (in `prepare.js`/`prove-secure.js`):** PBKDF2, then derive `m/44'/313'/n'/0'`,
  auto-scanning the account index `n` (0–99) to match the old address.

Security note: this proves knowledge of the **`m/44'/313'/n'/0'` node**, not the raw seed. Because
hardened derivation is one-way, an attacker holding the *leaked final key* still cannot produce
that node — so it remains a valid ownership signal for the incident.

## Use it (same command as the full runner)
```bash
# hardened (mnemonic at a hidden prompt):
./run-proof-secure.sh <oldAddr 0x..|zil1..> <newAddr> <domain dec|0x..>
# or quick (throwaway seeds only):
./run-proof.sh "<mnemonic>" <oldAddr> <newAddr> <domain>
```
No account-index argument — it auto-detects and prints it.

## The proving key (not in git)
`circuit_final.zkey` (**247 MB**) exceeds GitHub's 100 MB repo limit, so it's hosted in the
external bucket (GCS). Download it into this folder before running:
```
curl -L -o circuit_final.zkey https://storage.googleapis.com/bkt-p-zkproof-files-001/groth16/circuit_final.zkey
sha256sum circuit_final.zkey   # compare to the published checksum
```
It contains no secrets (a proving key is public material). `vk.json` + `verifier.sol` are in the repo.

## Requirements
- Node.js (first run installs `@scure/bip39`, `@scure/bip32`, `bip39`, `snarkjs` 0.7.6).
- Proving: **~15 s, ~7 GB RAM**. Disk: 247 MB (key) + deps.

## Reproduce / verify the circuit
`circuit.circom` + `bip32lib.circom` are the source; compile with circom 2.2.3 + the pinned includes
(0xPARC circom-ecdsa @ d87eb70, circomlib 2.0.2, Electron-Labs sha512 @ be9f01d). The
prover-supplied bit inputs are `b*(b-1)===0` constrained (audit-hardening).

## Files
- `run-proof-secure.sh` / `prove-secure.js` — hardened runner (masked stdin, in-memory).
- `run-proof.sh` / `prepare.js` — quick runner (argv; testing only).
- `circuit.circom` + `bip32lib.circom` — minimal circuit source.
- `circuit_js/` — witness generator (wasm) for the minimal circuit.
- `vk.json`, `verifier.sol` — Groth16 verification key + on-chain verifier (`uint[3]` = `[old,new,domain]`).
- `print_submit.js` — prints on-chain submission/claim instructions.
