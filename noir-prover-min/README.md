# Zilliqa seed-ownership zk-proof runner — Noir / UltraHonk, minimal circuit

The **Noir** counterpart of `../groth16-prover-min`. **Identical statement, inputs, and public
interface** (`[expectedAddr, newAddr, domain]`) — it differs only in the proof system: Aztec's
**Barretenberg / UltraHonk** (plonkish, universal setup).

> Why this variant exists: on this circuit it is **far lighter on RAM than Groth16**. Measured CLI
> run (22-thread x86_64): witness+prove peaks at **~0.42 GB in ~7.8 s** (prove step 5.0 s / 0.42 GB),
> vs snarkjs Groth16's **~6.5 GB in ~23 s** (prove step 14.6 s / 6.5 GB) — **no per-circuit key and no
> ceremony**. That RAM profile is what makes it **mobile-viable**. The cost is a bigger proof
> (~14.7 KB) and a **~2.58 M-gas** on-chain verifier (vs ~250 K for Groth16). Provided for the
> no-ceremony / mobile case; Groth16-min stays the cheapest-on-chain option.

## What it proves
Same as `../groth16-prover-min`: the `m/44'/313'/n'/0'` parent node (private) → final hardened
step `0'` in-circuit → `secp256k1` → `SHA-256[-20:]` → address `== old`, bound to `newAddr` +
`domain`. Public inputs `[expectedAddr, newAddr, domain]`. The seed → parent-node derivation and
account-index auto-scan happen **off-circuit** in `prepare.js`.

## Toolchain (install once)
```bash
# 1) install the version managers (these only edit ~/.bashrc)
curl -sL https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash
curl -sL https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash
# 2) put them on PATH in THIS shell (an already-open shell won't see the ~/.bashrc
#    change — either run this or open a new terminal)
export PATH="$HOME/.nargo/bin:$HOME/.bb:$PATH"
# 3) install the pinned versions (do NOT chain these onto the curl above — bbup/noirup
#    aren't on PATH until step 2)
noirup -v 1.0.0-beta.19
bbup   -v 4.2.0-aztecnr-rc.2
# verify: nargo --version -> 1.0.0-beta.19 ; bb --version -> 4.2.0-aztecnr-rc.2
```
Node.js is also needed (first run installs `@scure/bip32`, `@scure/bip39`).

## Use it (same command shape as every other runner)
```bash
./run-proof-secure.sh <oldAddr 0x..|zil1..> <newAddr> <domain dec|0x>   # hardened (hidden mnemonic prompt)
./run-proof.sh "<mnemonic>" <oldAddr> <newAddr> <domain>                # quick (throwaway seeds only)
```
No account-index argument — `prepare.js` auto-detects it. Both produce `target/proof` +
`target/public_inputs`, verify locally, and print on-chain submission instructions
(`print_submit.js` → `calldata_proof.txt` / `calldata_pubs.txt`).

Canonical `domain` = Zilliqa EVM mainnet chainId `32769` (or `keccak(chainId, claimContract)`
once the claim contract is deployed).

## On-chain
`verifier.sol` is the generated **`HonkVerifier`**: `verify(bytes _proof, bytes32[] _publicInputs)`,
publicInputs = `[old, new, domain]`. **~2.58 M gas** to verify (+ calldata for the ~14.7 KB proof).
The claim contract must read old/new/domain from the public inputs and call `verify()` itself.

**Interface vs the circom variants (for auditors):** the public inputs are the *same triple in the
same order*, but the Solidity ABI differs — `HonkVerifier` takes `bytes32[] _publicInputs`, whereas
the Groth16/PLONK verifiers take `uint256[3] _pubSignals`. Binding of `new`/`domain` also differs:
the circom circuits constrain them as witness products, while this circuit uses in-circuit
`assert(new_addr != 0)` / `assert(domain != 0)` and relies on Honk's keccak transcript to bind all
public inputs to the proof. Both are sound — `secure_core_test.sh` demonstrates a tampered
`new`/`domain` is rejected — but the *mechanism* is different, so don't read the bare `!= 0` asserts
as the whole binding.

## Reproduce / verify the circuit
`src/main.nr` is the source; deps are pinned (see `build-circuit.sh`). Run:
- `./build-circuit.sh` — compiles with the pinned nargo/bb + libs and prints the **VK hash**;
  confirm it equals `1bbdaf1c92714c3a99645c7beb5ed5dc2b06c298068518653e42d6248e06bde0`.
- `./secure_core_test.sh` — proves the all-zero test vector verifies **and** that tampering with
  `new`/`domain` is rejected (the binding property).

## Trusted dependencies (in audit scope)
The heavy gadgets are third-party Noir libs (analogous to circom-ecdsa/sha512 in the Groth16
variant): **`noir_bigcurve` v0.13.0** (secp256k1), **`noir-bignum` v0.9.0**, **`sha256` v0.3.0**,
**`sha512` @ e92ffb4**, plus Barretenberg (UltraHonk). A soundness bug in any is load-bearing.

## Files
- `src/main.nr` — the minimal circuit (Noir).
- `prepare.js` — off-circuit derivation (mnemonic → parent node → `Prover.toml`), account auto-scan, BIP-39 checksum.
- `run-proof-secure.sh` — hardened runner (hidden prompt; shreds `Prover.toml`/witness).
- `run-proof.sh` — quick runner (argv; testing only).
- `print_submit.js` — formats Honk calldata + claim instructions.
- `build-circuit.sh` — reproducible compile + VK-hash check.
- `secure_core_test.sh` — self-test (correct triple verifies; tampered new/domain rejected).
- `setup.sh` — fetches the one untagged dep (`sha512`) at its pinned commit.
- `verifier.sol` — generated on-chain `HonkVerifier`.
- `vk.bin` — keccak-transcript verification key (binary bb format; used by `bb verify` and matching `verifier.sol`).

## Security notes
- **Airgapped, amnesic OS for real seeds.** Unlike the Groth16 in-memory runner, `nargo` reads
  inputs from `Prover.toml`, so the parent node is briefly on disk. There is therefore **no
  in-memory `prove-secure.js`** like the circom variants; instead `run-proof-secure.sh` does the
  hidden-prompt + `shred` in bash. Still treat the machine as crown-jewel (Tails / live USB, ideally
  tmpfs).
- Only the addresses/domain and the `proof`/`public_inputs`/`calldata` are safe to move off the
  airgapped box — they reveal nothing about the seed.
- This is a **prototype**; audit the pinned deps and measure the on-chain verifier gas on your
  target chain before production use.
