# Ceremony operator

The operator runs the Groth16 phase-2 trusted-setup ceremony: create the initial key, verify and
promote each contribution, then apply the final beacon and publish the results. Three commands, run
by hand.

Download the **whole `operator/` folder** (`init.sh`, `verify-contribution.sh`, `finalize.sh`,
`package.json`, `package-lock.json`).

## Setup

Once, from inside this folder:

```bash
npm ci   # installs the pinned snarkjs into node_modules/ (from package-lock.json)
```

snarkjs is a **local** dependency, not a global command — run any manual snarkjs command through
`npx snarkjs …` (the scripts call the local copy directly). The scripts also run `npm ci` themselves
on first use, but the manual pre-checks below need it done first.

## Public inputs

All three steps need two public inputs — **`circuit.r1cs`** and **`pot.ptau`** — large binaries,
git-ignored here. Download both into this folder first:

```bash
# minimal circuit r1cs (~127 MB) — or recompile ../../groth16-prover-min/circuit.circom (circom 2.2.3 + pinned includes)
curl -L -o circuit.r1cs https://storage.googleapis.com/bkt-p-zkproof-files-001/groth16/circuit.r1cs
# canonical Hermez powers-of-tau, 2^21 (~2.3 GB); 2^20 is the minimum for this ~679k-constraint circuit
curl -L -o pot.ptau https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_21.ptau
npx snarkjs powersoftau verify pot.ptau   # full cryptographic check (needs Setup's npm ci); slow (~30–90 min)
b2sum pot.ptau                            # fast alternative: cross-check the blake2b vs the published value below
sha256sum circuit.r1cs                    # record this — it pins the circuit in the transcript (init.sh also prints it)
```

**Confirming `pot.ptau` is the genuine public file.** `b2sum pot.ptau` (BLAKE2b-512) must equal the value
Hermez/iden3 publishes for `powersOfTau28_hez_final_21.ptau`. That reference is in the **snarkjs README**
(<https://github.com/iden3/snarkjs>, the *Powers of Tau* NOTE — "Prepared (phase2) Ptau files for bn128
with 54 contributions and a beacon can be found here"):

```
9aef0573cef4ded9c4a75f148709056bf989f80dad96876aadeb6f1c6d062391f07a394a9e756d16f7eb233198d5b69407cca44594c763ab4a5b67ae73254678
```

A matching hash confirms you have the real file — instant, and independent of the slow `powersoftau
verify`. Record this blake2b (and the filename) as the ptau's fingerprint in the transcript.

## Beacon (pre-committed)

The finalization **beacon** is fixed **here, before the ceremony begins** — so no one can cherry-pick it:

> **Beacon = the hash of the first Ethereum mainnet block whose timestamp is ≥ `2026-09-04 14:00:00 UTC`,**
> taken once that block is **finalized** (~2 epochs / ~13 min after it is produced). Expected height
> ≈ **25,904,400** — an estimate only; the **timestamp rule, not the height, is binding**.

The value is unknowable until that block exists, so neither any contributor nor the operator can predict
or influence it. Collect and verify **all** contributions before that time; then apply it in step 3.

The beacon is applied with a fixed **`numIterationsExp = 10`** (2¹⁰ hash iterations) — pinned here too, so
the *whole* beacon is pre-committed, not just the block. Both values (the block hash and the iteration
count) are recorded in the published `transcript.md`; a verifier needs **both** to re-derive and check the
beacon step, which is what makes it publicly verifiable.

## 1. Initialize — once, at the start
```bash
./init.sh circuit.r1cs pot.ptau
```
Creates **`current.zkey`** (0 contributions) via `groth16 setup`, and prints the `circuit.r1cs`
sha256 to record in the transcript. Publish `current.zkey` for the **first** contributor to download.

## 2. After each upload — verify, then promote

Retrieve the contributor's uploaded `contribution.zkey` from the **Google Drive folder** into this
folder, then verify it **before** promoting:
```bash
./verify-contribution.sh <contribution.zkey> circuit.r1cs pot.ptau
```
Confirms the upload is a valid key for this circuit and prints its contribution chain. Check the
chain equals your **published transcript + exactly one new entry** (rejects forks/rollbacks), then
`mv contribution.zkey current.zkey` and publish it as the new current key for the next contributor.

## 3. Finalize — once, at the end (the beacon)

After all contributions are collected, apply the **pre-committed beacon** (see **Beacon
(pre-committed)** above) — a public value from a future source fixed before the ceremony, so it's
unbiasable. Look up the announced block (first ETH mainnet block with timestamp ≥ 2026-09-04
14:00:00 UTC), **wait for it to finalize**, take its `0x…` block hash, and **drop the `0x`** so you
have 64 hex chars. Then verify + export:

```bash
./finalize.sh <contribution.zkey> circuit.r1cs pot.ptau <64-hex-block-hash-no-0x> 10
```

Produces, in this folder:
- `final.zkey` — the **production proving key** (this is what ships in `../../groth16-prover-min/` as `circuit_final.zkey`),
- `vk.json` — the verification key,
- `verifier.sol` — the on-chain verifier contract,
- `transcript.md` — a **ready-to-publish transcript** (r1cs + ptau hashes, beacon value + iterations, final-artifact hashes, and the full `zkey verify` contribution chain — each step's name **and contribution hash**, plus the beacon params). Fully auto-filled; just commit it to GitHub.

> **Deploying into the zq2 escrow:** `finalize.sh` emits the **stock** snarkjs `verifier.sol` (a standalone
> `Groth16Verifier` with `public verifyProof`). The zq2 escrow uses an **integrated** variant
> (`verifyProof` is `internal`, inherited by the escrow, with a `bool isValid; … return isValid;` wrapper).
> So **do not copy the file wholesale** — port only its **26 VK constants** (`alpha/beta/gamma/delta` +
> `IC0..IC4`) into the escrow's integrated verifier, leaving the `internal`/`isValid` wrapper intact
> (see `Zilliqa/zq2` PR #3744 for the exact swap).

**What goes where.** `transcript.md` is small text — **publish it on GitHub** (it carries the
`circuit.r1cs` sha256 that pins the circuit, every contributor's hash, and the beacon value +
iterations). The keys are large and exceed GitHub's 100 MB limit, so **host them on the bucket**:
`final.zkey` is required for verification (it embeds the whole contribution chain); keeping each
intermediary `current.zkey`/`contribution.zkey` there too is optional but recommended, so anyone can
replay the chain step by step. (`circuit.r1cs` and the 2^21 `pot.ptau` are the same public inputs
used to build the ceremony.)

**Independent verification.** Anyone reproduces the circuit, checks its `sha256` equals the
transcript's, then runs `npx snarkjs zkey verify circuit.r1cs pot.ptau final.zkey` — a `ZKey Ok!`
cryptographically validates the entire contribution chain, and the printed contributions, **per-step
hashes**, and order must match the transcript. **Each contributor** confirms their own step directly:
the hash `contribute.sh` printed to them appears verbatim at their entry in that output. (Keeping the
intermediary `current.zkey`/`contribution.zkey` on the bucket is still useful for a full step-by-step
replay, but a contributor doesn't need them to confirm their own hash.)

## Files

- `init.sh` — create the initial `current.zkey` (`groth16 setup`), run once at the start.
- `verify-contribution.sh` — verify an uploaded contribution before promoting it to `current.zkey`.
- `finalize.sh` — final beacon step (beacon → verify → export `vk.json`/`verifier.sol`/`transcript.md`), run once at the end.
