# Ceremony contributor

Command-line tool to contribute to the Groth16 phase-2 trusted-setup ceremony. You download the
current key, run one command to mix in your randomness, and upload the result. Only one honest
contributor is needed for the whole setup to be secure, so it is worth doing carefully.

This folder is everything a contributor needs — download the **whole `contributor/` folder**
(`contribute.sh`, `contribute.js`, `package.json`, `package-lock.json`); the operator's scripts are
not required.

## Use it (3 steps — download & upload are manual)

**All downloads come from the bucket; the Google Drive folder is for uploads only.**

1. **Download `current.zkey`** into this folder — from the bucket (~358 MB for the minimal circuit):
   ```bash
   curl -L -o current.zkey https://storage.googleapis.com/bkt-p-zkproof-files-001/groth16/current.zkey
   ```
2. **Run:**
   ```bash
   ./contribute.sh
   ```
   The first run installs snarkjs via `npm ci` (see **Running air-gapped** for offline use). It then
   asks for your name/handle and some random text, mixes that with your machine's cryptographic RNG,
   and writes **`contribution.zkey`**. Takes a few minutes and several GB of RAM.
3. **Upload `contribution.zkey`** to the ceremony's **Google Drive folder** —
   <https://drive.google.com/drive/folders/18Et2q7lXeH4IhCwGlWIMTHT7npFLp5ji> — and **report the
   printed contribution hash** to the operator so it can be checked against the public transcript.

That's it — everything between download and upload is automated.

## What it does (and why it's safe)

- Your contribution's randomness = the text you type **plus 64 bytes from the OS CSPRNG**. The
  CSPRNG is what secures it; the typed text is supplementary.
- The tool never sees or needs any seed/private wallet key — a proving key is **public material**;
  the only secret is the fresh randomness you mix in, which must be **destroyed** afterwards.
- The **contribution hash** is your public receipt: it lets anyone confirm your contribution is in
  the chain, and lets you confirm the operator didn't drop or alter it.

## Beacon (pre-committed)

For transparency, the ceremony's finalization **beacon** is fixed in advance — announced here before
any contribution, so it can't be cherry-picked:

> the hash of the first **Ethereum mainnet** block with timestamp ≥ `2026-09-04 14:00:00 UTC`
> (taken once finalized; expected height ≈ 25,904,400 — the timestamp rule is what's binding),
> applied with a fixed **2¹⁰ iterations**.

You don't do anything with it — the operator applies it at the very end. But because it's public and
unknowable until that block exists, you (or anyone) can later confirm the published final key was
produced with **exactly this beacon** (block hash + iteration count, both published in the transcript)
and nothing else.

## Recommended hygiene

- Run on a **clean machine, offline** if you can; **reboot afterwards** so your entropy doesn't
  linger in memory. (Less critical here than when handling an actual wallet seed — no wallet secret
  is involved in a contribution — but good practice.)
- Before contributing, you can optionally **verify the key you downloaded**: its latest contribution
  hash should equal the last entry in the operator's published transcript. Full cryptographic
  verification also needs the **`circuit.r1cs`** and the **2²¹ powers-of-tau** — get both like this,
  then verify:
  ```bash
  npm ci                                  # once — installs the pinned local snarkjs
  # circuit.r1cs — from the bucket (same source as current.zkey):
  curl -L -o circuit.r1cs https://storage.googleapis.com/bkt-p-zkproof-files-001/groth16/circuit.r1cs
  # the canonical 2^21 Hermez powers-of-tau (~2.3 GB):
  curl -L -o pot.ptau https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_21.ptau
  npx snarkjs zkey verify circuit.r1cs pot.ptau current.zkey   # expect "ZKey Ok!"
  ```
  This is **optional** — the operator re-verifies every upload anyway. (snarkjs is the pinned local
  dependency, so `npx snarkjs`, not a bare `snarkjs`.)

## Running air-gapped (offline)

The contribution itself makes **no network calls** — but `contribute.sh`'s *first* run does
`npm ci`, which **needs internet**. So on an air-gapped machine, bring the dependency with you:

1. **On a networked machine:** get this folder and run `npm ci` inside it — that installs the
   **exact, integrity-checked** snarkjs tree pinned in `package-lock.json` into `node_modules/`.
2. Copy the **whole folder, now including `node_modules/`**, onto removable media, together with the
   ceremony's current `current.zkey`.
3. **On the air-gapped machine:** copy it over and run `./contribute.sh`. It sees `node_modules/`
   already present, **skips `npm ci`**, and runs fully offline.
4. Carry `contribution.zkey` back out on the same media and upload it from a networked machine.

(`node_modules/` is git-ignored and never committed — you always rebuild it from the committed
`package.json` + `package-lock.json`, so every machine gets a byte-identical dependency tree.)

## Requirements

- **Node.js**. First run installs `snarkjs` via `npm ci` from the pinned `package-lock.json`
  (exact, integrity-checked). For offline/air-gapped use, pre-bundle `node_modules/` first — see
  **Running air-gapped** above.
- **~several GB free RAM** (the script sets a 16 GB Node heap) and ~358 MB disk for each of the
  input and output keys (minimal circuit). The contribution itself takes a few minutes.

## Files

- `contribute.sh` — installs deps (first run) and runs the contributor tool with a large Node heap.
- `contribute.js` — gathers entropy, runs `snarkjs zkey contribute`, prints your contribution hash + next steps.
