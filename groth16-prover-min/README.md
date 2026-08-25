# Zilliqa seed-ownership zk-proof runner — Groth16, minimal circuit

Prove your seed controls a compromised Zilliqa account, bound to a safe destination + domain, without
revealing the seed — on the **minimal circuit**: only the **final BIP-32 CKD step** is done in-circuit;
the seed → level-4 parent node is derived **off-circuit**.

The final step is **configurable** by the public `isHardened` bit, so the same circuit covers both
legacy Zilliqa wallet families:

| `isHardened` | wallet | path | parent fed to circuit | final step |
|---|---|---|---|---|
| `1` | **Ledger** (all-hardened) | `m/44'/313'/n'/0'/0'` | `m/44'/313'/n'/0'` | hardened `/0'` |
| `0` | **standard BIP-44** (hot wallets: Bearby, Zillet, …) | `m/44'/313'/n'/0/i` | `m/44'/313'/n'/0` | non-hardened `/i` |

The two modes differ **only** in the HMAC-SHA512 preimage (`0x00‖privkey` vs `compress(privkey·G)`) and
one index bit; everything after HMAC (child key → secp256k1 pubkey → SHA-256[-20:] address) is identical.
Cost of configurability: one extra secp256k1 scalar-mult → **~679k constraints** (524,094 non-linear +
155,324 linear), up from 427k. Proving ≈ 25–35 s at ~8 GB with a **~358 MB** key.

## What it proves
`level-4 parent node --(final CKD step, hardened or not)--> key --secp256k1--> pubkey --SHA-256[-20:]--> address == <old>`, bound to `newAddr` + `domain`.
- **Private inputs:** the parent node's private key + chain code (256+256 bits, each **binary-constrained**), and `addrIndex` (the final path index; `0` for Ledger, the BIP-44 address_index otherwise, `< 2^31`).
- **Public inputs (`uint[4]`):** `[expectedAddr(old), newAddr, domain, isHardened]`.
- **Canonical `domain`:** Zilliqa EVM mainnet chainId `32769` (or `keccak(chainId, claimContract)` once the claim contract is deployed).
- **Off-circuit (in `prepare.js`/`prove-secure.js`):** PBKDF2, then auto-detect the wallet style — scan Ledger accounts `m/44'/313'/n'/0'/0'` (n<100), then standard BIP-44 leaves `m/44'/313'/a'/0/i` (a<5, i<100) — to match the old address, emitting the right parent + `isHardened` + `addrIndex`.
- **Address range checks:** both `expectedAddr` and `newAddr` are constrained to 160 bits (a real 20-byte address), so the proof's committed destination matches the on-chain `address(uint256)` truncation. `domain` is a separator, not an address, so it is deliberately left unbounded.
- **BIP-32 conformance:** the final CKD step rejects the (astronomically rare, ~2⁻¹²⁸) invalid cases — HMAC left half `IL ≥ n` or `childPriv == 0` — per the standard; `@scure`'s `HDKey.derive` mirrors the same rejection off-circuit.

### Security note — the two modes are NOT equally strong
- **Hardened (`isHardened=1`)** proves knowledge of the `m/44'/313'/n'/0'` node. Because hardened
  derivation is one-way, an attacker holding the **leaked final key** still cannot produce that node —
  full-strength ownership signal (the biased-nonce Ledger case).
- **Non-hardened (`isHardened=0`)** proves knowledge of the `m/44'/313'/n'/0` change node. This is fine
  as an *ownership-for-migration* proof, but it is **weaker against a leaked-key adversary**: with the
  leaked child key **and** the parent xpub, the parent is recoverable. So a **claim contract that guards
  Ledger biased-nonce addresses should `require(isHardened == 1)`** for those addresses (isHardened is
  public exactly so the contract can enforce this).

## Use it
```bash
# hardened runner (mnemonic at a hidden prompt) — works for either wallet family, auto-detected:
./run-proof-secure.sh <oldAddr 0x..|zil1..> <newAddr> <domain dec|0x..>
# or quick (throwaway seeds only):
./run-proof.sh "<mnemonic>" <oldAddr> <newAddr> <domain>
```
No path/index argument — it auto-detects the derivation style, account, and index, and prints them.

## The proving key (not in git)
`circuit_final.zkey` (**~358 MB**) exceeds GitHub's 100 MB limit, so it's hosted in the external bucket
(GCS). Download it into this folder before running:
```
curl -L -o circuit_final.zkey https://storage.googleapis.com/bkt-p-zkproof-files-001/groth16/circuit_final.zkey
sha256sum circuit_final.zkey   # compare to the published checksum
```
A proving key is public material (no secrets). `vk.json` + `verifier.sol` are in the repo.

> **⚠ The bucket key must be the CEREMONY output.** The zkey produced by `build-circuit.sh` + a local
> `snarkjs zkey contribute` is a **single-contributor DEV key — not safe for production** (its toxic
> waste wasn't destroyed by an N-party ceremony). The production key comes from running the Groth16
> phase-2 ceremony (Zilliqa + Hacken + others) on `circuit.r1cs`; regenerate `vk.json` + `verifier.sol`
> from that final zkey before deploying.

## Requirements
- Node.js (first run installs `@scure/bip39`, `@scure/bip32`, `bip39`, `snarkjs` 0.7.x).
- Proving: **≈ 25–35 s, ~8 GB RAM**. Disk: ~358 MB (key) + deps.

## Reproduce / verify the circuit
`circuit.circom` + `bip32lib.circom` are the source; circom 2.2.3 + pinned includes (0xPARC circom-ecdsa
@ d87eb70, circomlib 2.0.2, Electron-Labs sha512 @ be9f01d). Prover-supplied bit inputs are
`b*(b-1)===0` constrained (audit-hardening).
- `./build-circuit.sh` — recompile from the pinned sources and confirm the `wasm`/`r1cs` are
  **byte-identical** to the shipped ones (`circuit.wasm` md5 `c4281b70…`, `circuit.r1cs` 132,857,964 B).
- `node secure_core_test.js` — self-test on the throwaway all-zero mnemonic: proves **both** the Ledger
  hardened path **and** a standard BIP-44 non-hardened path (addrIndex 3) verify, and that tampering with
  `newAddr`/`domain` fails (binding). Needs the zkey.

## Regenerate the proving key (r1cs → zkey)
```bash
./build-circuit.sh /tmp/build            # -> /tmp/build/circuit.r1cs (+ circuit_js/circuit.wasm)
# then, with a 2^20 powers-of-tau (e.g. powersOfTau28_hez_final_20.ptau):
snarkjs groth16 setup circuit.r1cs pot20_final.ptau circuit_0000.zkey
snarkjs zkey contribute circuit_0000.zkey circuit_final.zkey -n=dev -e="<entropy>"   # DEV; prod = ceremony
snarkjs zkey export verificationkey circuit_final.zkey vk.json
snarkjs zkey export solidityverifier  circuit_final.zkey verifier.sol
```

## Files
- `run-proof-secure.sh` / `prove-secure.js` — hardened runner (masked stdin, in-memory).
- `run-proof.sh` / `prepare.js` — quick runner (argv; testing only).
- `circuit.circom` + `bip32lib.circom` — minimal configurable circuit source.
- `circuit_js/` — witness generator (wasm).
- `vk.json`, `verifier.sol` — Groth16 verification key + on-chain verifier (`uint[4]` = `[old,new,domain,isHardened]`).
- `print_submit.js` — prints on-chain submission/claim instructions.
- `build-circuit.sh` — reproducible compile from pinned sources + byte-identical check.
- `secure_core_test.js` — dual-mode binding self-test on a throwaway seed (needs the zkey).
