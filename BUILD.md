# Building the recovery app

The Flutter app (`flutter/`) proves the minimal Zilliqa-recovery circuit with **two interchangeable
backends**:

- **Groth16** (circom + arkworks, via mopro) — `computeGroth16Proof`
- **Noir / UltraHonk** (Barretenberg, via `noir_rs`) — `computeNoirProof`

Both are compiled into the same Rust library and the same app; you pick which one the UI calls (see
[Choosing the backend](#choosing-the-backend)). This guide covers the Noir variant and the shared
build. Branch: **`feature/noir-implementation`**.

> Standalone CLI provers (no app) live in `groth16-prover-min/`, `plonk-prover-min/`,
> `noir-prover-min/` — each with its own README. This file is for building the **app**.

---

## TL;DR (Linux desktop, Noir)

```bash
# toolchain: Rust + Flutter (see Prerequisites), then:
git checkout feature/noir-implementation
cp groth16-prover-min/circuit_js/circuit.wasm test-vectors/circom/circuit.wasm   # build.rs input
cd flutter && flutter pub get && flutter build linux --release
./build/linux/x64/release/bundle/zkp_recovery_app                               # runs; no LD_PRELOAD
```

First launch downloads the Barretenberg SRS (~once, to `~/.bb-crs`); generating a proof needs the
addresses + mnemonic entered in the UI.

---

## Prerequisites

| Tool | Version used | Install |
|---|---|---|
| Rust | 1.97.1 (needs **≥ 1.91**) | `rustup update stable` |
| Flutter | 3.47.0 stable | https://docs.flutter.dev/get-started/install |
| Linux desktop deps | — | `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev` |
| mopro CLI | latest | `cargo install mopro-cli` — **only for Android/iOS bindings** |
| Node.js | 18+ | only for the circom CLI provers, not the app |

The **Noir backend needs no extra toolchain to build the app**: the `noir_rs` crate
(`Cargo.toml`, pinned to `v1.0.0-beta.19`, feature `barretenberg`) downloads a **prebuilt
Barretenberg static lib** (`4.2.0-aztecnr-rc.2`, from an AztecProtocol/aztec-packages release) at
`cargo build` time — so you need network + `curl`, but no C++ build of Barretenberg. (`nargo`/`bb`
are only needed to *recompile the circuit*, see [Verifying](#verifying-the-build).)

---

## One-time repo setup

`build.rs` runs `rust_witness::transpile_wasm("./test-vectors/circom")`, so the circom witness
generator must be present even for a Noir-only build. It's already in the repo — just copy it:

```bash
cp groth16-prover-min/circuit_js/circuit.wasm test-vectors/circom/circuit.wasm   # md5 fd66c1a...
```

The **247 MB `circuit_final.zkey` is NOT needed to build** — it's downloaded at runtime by the app
(Groth16 path) or placed manually only for the Rust self-test. If you want it:

```bash
curl -L -o test-vectors/circom/circuit_final.zkey \
  https://storage.googleapis.com/bkt-p-zkproof-files-001/groth16/circuit_final.zkey
```

The **Noir circuit** is bundled precompiled as `flutter/assets/circuit_min.json` (the ACIR) — no
step needed; it's reproducible via `noir-prover-min/build-circuit.sh` (VK hash `1bbdaf1c…`).

---

## Build & run — Linux desktop  (verified)

```bash
cd flutter
flutter pub get
flutter build linux --release
```

Output: `flutter/build/linux/x64/release/bundle/zkp_recovery_app`. Run it directly:

```bash
./build/linux/x64/release/bundle/zkp_recovery_app
```

The Barretenberg static-TLS launch fix is **baked into the runner's CMake** (`linux/CMakeLists.txt`
startup-loads the FFI lib; `linux/runner/stackfix.cc` forces ≥4 MB thread stacks), so a plain launch
works — **no `LD_PRELOAD`, no wrapper**.

**WSL2 note:** these binaries are built against glibc 2.39, so a WSL2 distro must be **Ubuntu 24.04+**;
the GUI needs **Windows 11 / WSLg** (Win10 needs an external X server). See `compare/README-WSL2.md`.

---

## Build & run — Android / iOS

Mobile uses the mopro binding flow (see the root `README.md` "Getting Started"). In short:

```bash
rustup target add aarch64-linux-android x86_64-linux-android   # + aarch64-apple-ios for iOS
cargo install mopro-cli
mopro build          # cross-compiles the Rust lib (incl. Barretenberg) for the mobile targets
mopro update         # refreshes the generated bindings in the platform templates
cd flutter && flutter build apk        # or: flutter build ios   (needs macOS + Xcode)
```

The same `circuit.wasm` copy in [One-time setup](#one-time-repo-setup) is required. iOS builds need
macOS. Mobile targets were **not validated in this environment** — follow the current
[mopro docs](https://zkmopro.org/docs/next/setup/flutter-setup) if anything drifts.

---

## Choosing the backend

The only app-flow difference between the two variants is one call in
`flutter/lib/widgets/onboarding_stepper_page.dart`:

```dart
await ProofService.instance.computeNoirProof(...)      // Noir / UltraHonk
// vs
await ProofService.instance.computeGroth16Proof(...)   // Groth16
```

Both functions live in `flutter/lib/services/proof_service.dart` and take the same arguments; the
Rust backends are `src/noir.rs` (Noir) and `src/circom.rs` + mopro (Groth16). Switch the one line and
rebuild.

---

## Runtime notes / first run

- **SRS (Noir):** with `srsPath: null` (default), `noir_rs` downloads the ~128 MB BN254 SRS
  **into memory on every launch** (it does *not* persist it — the `~/.bb-crs` folder is the separate
  `bb` CLI cache). To avoid that and enable offline, bundle it — see [Offline SRS](#offline-srs).
- **zkey (Groth16):** the app downloads `circuit_final.zkey` (247 MB) into its cache dir on first use.
- **Memory:** Noir proving peaks ~1.3 GB in-app; Groth16 ~1 GB. Fine on ≥4 GB.

---

## Offline SRS

The Noir prover needs the BN254 SRS — a **universal** setup (same file for every circuit; each circuit
uses a prefix sized to it). This circuit needs **~128 MB** (262,144 gates × 8 SRS points × 64 B). By
default the app downloads it per launch; to prove **fully offline** (and skip that download), bundle it:

```bash
scripts/fetch-srs.sh                     # -> flutter/assets/srs_g1.srs (~140 MB): downloads the
                                         #    raw .dat and converts it to the bincode .srs format
# then uncomment  "- assets/srs_g1.srs"  in flutter/pubspec.yaml
cd flutter && flutter build linux --release
```

- The file is **git-ignored** (~140 MB > GitHub's 100 MB limit), so the script produces it at build
  time; `flutter build` bakes it into the app bundle.
- `fetch-srs.sh` downloads the raw G1 SRS prefix (`.dat`) from `https://crs.aztec.network/g1.dat`
  and converts it to `srs_g1.srs` via `cargo run --bin gen_srs` — the same **`.srs`** format the
  upstream mopro example ships. (The adapter also accepts a raw `.dat` directly, but `.srs` keeps us
  aligned with mopro.) Don't reuse the 16 MB `~/.bb-crs/bn254_g1.dat` — too few points → panics.
- `proof_service.dart` auto-detects the bundled `assets/srs_g1.srs` and passes it as `srsPath`; if it
  isn't bundled, `srsPath` stays `null` and the app downloads the SRS — so the default build works.
- For an **airgapped** device there's no first-run download to fall back on, so bundling (or
  side-loading the `.srs`) is required.

---

## Verifying the build

- **Circom/Groth16 backend** — `cargo test --release test_plonk` (needs
  `test-vectors/circom/circuit_final.zkey` present). Proves + verifies the min circuit end-to-end.
- **Noir circuit reproducibility** — `cd noir-prover-min && ./build-circuit.sh`. Recompiles the ACIR
  with the pinned `nargo`/`bb` and prints the VK hash; it must equal `1bbdaf1c…` and the compiled
  bytecode is byte-identical to `flutter/assets/circuit_min.json`. (Needs the Noir toolchain — see
  `noir-prover-min/README.md`.)

---

## Troubleshooting

- **`bbup`/`noirup` "command not found" right after install** — the installers only edit `~/.bashrc`;
  an already-open shell won't see it. Run `export PATH="$HOME/.nargo/bin:$HOME/.bb:$PATH"` (or open a
  new terminal) before `noirup -v 1.0.0-beta.19` / `bbup -v 4.2.0-aztecnr-rc.2`. Don't chain them onto
  the `curl … | bash`.
- **`bb: error converting into field Circuit::opcodes`** — wrong `bb` version. The app/circuit are
  beta.19; use **`bb 4.2.0-aztecnr-rc.2`**, not 5.0.0-nightly (that's beta.22).
- **`build.rs` fails / missing `circuit_*` symbols** — you skipped the `circuit.wasm` copy in
  [One-time setup](#one-time-repo-setup).
- **`failed to select a version for tokio`** — a stale `mopro_flutter_bindings/rust/Cargo.lock`; delete
  it and let cargo re-resolve.
- **`rustc … is not supported`** — run `rustup update stable` (need ≥ 1.91).
- **GUI won't open on WSL2** — Windows 11 (WSLg) + Ubuntu 24.04; see `compare/README-WSL2.md`.
