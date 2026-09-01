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
npx snarkjs powersoftau verify pot.ptau   # confirm it's the genuine public ceremony (needs Setup's npm ci)
sha256sum circuit.r1cs                    # record this — it pins the circuit in the transcript (init.sh also prints it)
```

## 1. Initialize — once, at the start
```bash
./init.sh <circuit.r1cs> <pot21.ptau>
```
Creates **`current.zkey`** (0 contributions) via `groth16 setup`, and prints the `circuit.r1cs`
sha256 to record in the transcript. Publish `current.zkey` for the **first** contributor to download.

## 2. After each upload — verify, then promote
```bash
./verify-contribution.sh <contribution.zkey> <circuit.r1cs> <pot21.ptau>
```
Confirms the upload is a valid key for this circuit and prints its contribution chain. Check the
chain equals your **published transcript + exactly one new entry** (rejects forks/rollbacks), then
`mv contribution.zkey current.zkey` and publish it as the new current key for the next contributor.

## 3. Finalize — once, at the end (the beacon)

After all contributions are collected, the operator applies the **beacon**. This is **not** a
contributor step: it applies a **public random value from a pre-committed future source** — a drand
round or a Bitcoin block hash whose round/height is chosen *after* contributions close (so you know
they're complete) but still lies in the **future** at that moment, so the value is unknowable and no
one — operator included — can grind or cherry-pick it. (What's fixed *after* the last contribution is
only *which* future round/height; the *value* must not yet exist.) Then it verifies and exports:

```bash
./finalize.sh <lastKey.zkey> <circuit.r1cs> <pot.ptau> <beaconHex64> [iterations=10]
```

Produces, in this folder:
- `final.zkey` — the **production proving key** (this is what ships in `../../groth16-prover-min/` as `circuit_final.zkey`),
- `vk.json` — the verification key,
- `verifier.sol` — the on-chain verifier contract,
- `transcript.md` — a **ready-to-publish transcript** (r1cs sha256, beacon value + iterations, final-artifact hashes, and the full ordered contribution chain from `zkey verify`). Fill in the two `[operator: …]` fields (ptau name, beacon source), then commit it to GitHub.

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
transcript's, then runs `snarkjs zkey verify circuit.r1cs pot.ptau final.zkey` — a `ZKey Ok!`
cryptographically validates the entire contribution chain, and the printed **ordered contributor
list** (names, newest first) must match the transcript. (`zkey verify` lists names/order and proves
validity; it does not print per-contribution hashes.) **Each contributor** confirms their own step
by hashing the intermediary key they produced and matching it to the receipt `contribute.sh` showed
them — which is why the operator keeps every `current.zkey`/`contribution.zkey` on the bucket.

## Files

- `init.sh` — create the initial `current.zkey` (`groth16 setup`), run once at the start.
- `verify-contribution.sh` — verify an uploaded contribution before promoting it to `current.zkey`.
- `finalize.sh` — final beacon step (beacon → verify → export `vk.json`/`verifier.sol`/`transcript.md`), run once at the end.
