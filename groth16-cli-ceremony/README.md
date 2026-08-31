# Ceremony contributor (terminal)

Command-line tool to contribute to the Groth16 phase-2 trusted-setup ceremony — the CLI
counterpart of the browser contributor. You download the current key, run one command to mix
in your randomness, and upload the result. Only one honest contributor is needed for the whole
setup to be secure, so it is worth doing carefully.

## Use it (3 steps — download & upload are manual)

1. **Download** the ceremony's current key into this folder as **`current.zkey`** (~358 MB for
   the minimal circuit), from wherever the operator published it.
2. **Run:**
   ```bash
   ./contribute.sh
   ```
   It asks for your name/handle and some random text, mixes that with your machine's
   cryptographic RNG, and writes **`contribution.zkey`**. Takes a few minutes and several GB of RAM.
3. **Upload** `contribution.zkey` to the coordinator, and **report the printed contribution hash**
   to the operator so it can be checked against the public transcript.

That's it — everything between download and upload is automated.

## What it does (and why it's safe)

- Your contribution's randomness = the text you type **plus 64 bytes from the OS CSPRNG**. The
  CSPRNG is what secures it; the typed text is supplementary.
- The tool never sees or needs any seed/private wallet key — a proving key is **public material**;
  the only secret is the fresh randomness you mix in, which must be **destroyed** afterwards.
- The **contribution hash** is your public receipt: it lets anyone confirm your contribution is in
  the chain, and lets you confirm the operator didn't drop or alter it.

## Recommended hygiene

- Run on a **clean machine, offline** if you can; **reboot afterwards** so your entropy doesn't
  linger in memory. (Less critical than the seed-proof runner — no wallet secret is involved —
  but good practice.)
- Before contributing, you can **verify the key you downloaded** matches the published transcript:
  its latest contribution hash should equal the last entry the operator published. (Full
  cryptographic verification, `snarkjs zkey verify circuit.r1cs <ptau> current.zkey`, also needs
  the r1cs and the 2^21 powers-of-tau — optional; the coordinator re-verifies every upload anyway.)

## Running air-gapped (offline)

The contribution itself makes **no network calls** — but `contribute.sh`'s *first* run does
`npm install`, which **needs internet**. So on an air-gapped machine, bring the dependency with you:

1. **On a networked machine:** get this folder and run `npm install` (or `npm ci`) inside it —
   that populates `node_modules/` with snarkjs.
2. Copy the **whole folder, now including `node_modules/`**, onto removable media, together with the
   ceremony's current `current.zkey`.
3. **On the air-gapped machine:** copy it over and run `./contribute.sh`. It sees `node_modules/`
   already present, **skips `npm install`**, and runs fully offline.
4. Carry `contribution.zkey` back out on the same media and upload it from a networked machine.

(`node_modules/` is git-ignored and never committed, so you always bring your own copy.)

## Requirements

- **Node.js**. First run installs `snarkjs`; for offline/air-gapped use, pre-bundle `node_modules/`
  first — see **Running air-gapped** above.
- **~several GB free RAM** (the script sets a 16 GB Node heap) and ~358 MB disk for each of the
  input and output keys (minimal circuit). The contribution itself takes a few minutes.

## Operator: running the ceremony

The operator does three things (the browser ceremony's coordinator automated these; in this
manual CLI flow they're run by hand). All three need two public inputs — **`circuit.r1cs`** and
**`pot.ptau`** — large binaries, git-ignored here. Download both into this folder first:

```bash
# minimal circuit r1cs (~127 MB) — or recompile ../groth16-prover-min/circuit.circom (circom 2.2.3 + pinned includes)
curl -L -o circuit.r1cs https://storage.googleapis.com/bkt-p-zkproof-files-001/groth16/circuit.r1cs
# canonical Hermez powers-of-tau, 2^21 (~2.3 GB); 2^20 is the minimum for this ~679k-constraint circuit
curl -L -o pot.ptau https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_21.ptau
snarkjs powersoftau verify pot.ptau   # confirm it's the genuine public ceremony
sha256sum circuit.r1cs                 # record this — it pins the circuit in the transcript (init.sh also prints it)
```

### 1. Initialize — once, at the start
```bash
./init.sh <circuit.r1cs> <pot21.ptau>
```
Creates **`current.zkey`** (0 contributions) via `groth16 setup`. Publish it for the **first**
contributor to download.

### 2. After each upload — verify, then promote
```bash
./verify-contribution.sh <contribution.zkey> <circuit.r1cs> <pot21.ptau>
```
Confirms the upload is a valid key for this circuit and prints its contribution chain. Check the
chain equals your **published transcript + exactly one new entry** (rejects forks/rollbacks), then
`mv contribution.zkey current.zkey` and publish it as the new current key for the next contributor.

### 3. Finalize — once, at the end (the beacon)

After all contributions are collected, the operator applies the **beacon**. This is **not** a
`contribute.sh` contribution: it applies a **public random value from a pre-committed future
source** — a drand round or a Bitcoin block hash whose round/height is chosen *after* contributions
close (so you know they're complete) but still lies in the **future** at that moment, so the value
is unknowable and no one — operator included — can grind or cherry-pick it. (What's fixed *after*
the last contribution is only *which* future round/height; the *value* must not yet exist.) Then it
verifies and exports the artifacts:

```bash
./finalize.sh <lastKey.zkey> <circuit.r1cs> <pot.ptau> <beaconHex64> [iterations=10]
```

Produces, in this folder:
- `final.zkey` — the **production proving key** (this is what ships in `../groth16-prover-min/` as `circuit_final.zkey`),
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

Contributor:
- `contribute.sh` — installs deps (first run) and runs the contributor tool with a large Node heap.
- `contribute.js` — gathers entropy, runs `snarkjs zkey contribute`, prints your contribution hash + next steps.

Operator:
- `init.sh` — create the initial `current.zkey` (`groth16 setup`), run once at the start.
- `verify-contribution.sh` — verify an uploaded contribution before promoting it to `current.zkey`.
- `finalize.sh` — final beacon step (beacon → verify → export `vk.json`/`verifier.sol`), run once at the end.
