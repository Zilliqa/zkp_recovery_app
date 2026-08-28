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

## Requirements

- **Node.js**. First run installs `snarkjs` (or bundle `node_modules/` for offline use).
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
`contribute.sh` contribution: it applies a **public, externally-fixed** random value (a drand
round or a future Bitcoin block hash — chosen *after* the last contribution) so the finalization
is unbiasable and publicly verifiable. Then it verifies and exports the artifacts:

```bash
./finalize.sh <lastKey.zkey> <circuit.r1cs> <pot.ptau> <beaconHex64> [iterations=10]
```

Produces, in this folder:
- `final.zkey` — the **production proving key** (this is what ships in `../groth16-prover-min/` as `circuit_final.zkey`),
- `vk.json` — the verification key,
- `verifier.sol` — the on-chain verifier contract.

> **Deploying into the zq2 escrow:** `finalize.sh` emits the **stock** snarkjs `verifier.sol` (a standalone
> `Groth16Verifier` with `public verifyProof`). The zq2 escrow uses an **integrated** variant
> (`verifyProof` is `internal`, inherited by the escrow, with a `bool isValid; … return isValid;` wrapper).
> So **do not copy the file wholesale** — port only its **26 VK constants** (`alpha/beta/gamma/delta` +
> `IC0..IC4`) into the escrow's integrated verifier, leaving the `internal`/`isValid` wrapper intact
> (see `Zilliqa/zq2` PR #3744 for the exact swap).

Publish those together with the **full contribution transcript** (every contributor's hash) and
the **beacon value + iterations** used, so anyone can reproduce and verify the whole setup.
(`circuit.r1cs` and the 2^21 `pot.ptau` are the same public inputs used to build the ceremony.)

## Files

Contributor:
- `contribute.sh` — installs deps (first run) and runs the contributor tool with a large Node heap.
- `contribute.js` — gathers entropy, runs `snarkjs zkey contribute`, prints your contribution hash + next steps.

Operator:
- `init.sh` — create the initial `current.zkey` (`groth16 setup`), run once at the start.
- `verify-contribution.sh` — verify an uploaded contribution before promoting it to `current.zkey`.
- `finalize.sh` — final beacon step (beacon → verify → export `vk.json`/`verifier.sol`), run once at the end.
