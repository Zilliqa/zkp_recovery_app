# TASKS DONE

## Scaffold Build Script With Prerequisite Checks

Create `scripts/build-macos.sh` in a new top-level `scripts/` directory that resolves the repo root from its own location, prints a `--help`/usage block listing its flags and prerequisites, and, before building anything, stops with an install hint when a required tool is missing (an arm64 macOS host via `uname -s`/`uname -m`, the Xcode command-line tools via `xcode-select -p`, `flutter`, CocoaPods `pod`, `cargo`/`rustup` with `aarch64-apple-darwin` listed by `rustup target list --installed`, `hdiutil`/`codesign`/`shasum`, and `mopro` with the hint `cargo install mopro-cli`), but only warns and carries on when the working tree is dirty or HEAD is not a release tag or a `release/*` branch. It also reads the authoritative `version:` from `flutter/pubspec.yaml` (without any `+build` suffix) and warns, naming each file and value, if the root `Cargo.toml` version or the `zkp_recovery_app` dependency version in `mopro_flutter_bindings/rust/Cargo.toml` differs. Verified by running the script with `--help`, running it on the current tree (expecting the 0.5.0/0.5.1 version warning and the git-state warning), and running it with one tool hidden from `PATH` (expecting a non-zero stop with the install hint).

**Verified:**

- `scripts/build-macos.sh` exists in a new top-level `scripts/` directory, is executable, and passes `bash -n` under both Homebrew bash 5.3 and the macOS system `/bin/bash` 3.2.
- The script resolves the repo root from its own location (`BASH_SOURCE[0]`/..): run from `/tmp`, it reports `Repo root: /Users/lucask/workspace-zilliqa/zkp_recovery_app` and reads the version files there.
- `scripts/build-macos.sh --help` exits 0 and prints a usage block listing its flag (`-h, --help`) and every prerequisite (arm64 macOS host, Xcode command-line tools, flutter, CocoaPods `pod`, `cargo`/`rustup` with `aarch64-apple-darwin`, `hdiutil`/`codesign`/`shasum`, `mopro` with `cargo install mopro-cli`), plus the warn-only conditions; an unknown argument exits 2 with the usage.
- The prerequisite checks run before any build step: a non-arm64/non-Darwin `uname -s`/`uname -m` stops the script; `xcode-select -p`, `flutter`, `pod`, `cargo`, `rustup`, `rustup target list --installed` containing `aarch64-apple-darwin`, `hdiutil`, `codesign`, `shasum` and `mopro` each produce an `ERROR: ... -- <install hint>` line when missing, and any missing tool makes the script exit 1.
- On the current tree with the real PATH (mopro not installed), the script prints `ERROR: mopro not found on PATH -- install it with: cargo install mopro-cli` and exits 1.
- On the current tree with a stub `mopro` on PATH, the script exits 0, reads version `0.5.0` from `flutter/pubspec.yaml`, and prints two version-mismatch warnings naming `Cargo.toml` (`0.5.1`) and the `zkp_recovery_app` dependency in `mopro_flutter_bindings/rust/Cargo.toml` (`0.5.1`), plus the dirty-tree warning and the "HEAD (user/lukasz/macos_dist) is neither a release tag (v*) nor a release/* branch" warning, and carries on.
- The pubspec version is read without a `+build` suffix (`version: "1.2.3+45"` parses to `1.2.3`).
- With `/opt/homebrew/bin` removed from PATH (hiding `flutter`), the script stops with exit 1 and `ERROR: flutter not found on PATH -- install Flutter (...)`; with `~/.cargo/bin` removed, it stops with exit 1 and install hints for `cargo`, `rustup` and `mopro`.
- In a throwaway clone checked out at `v0.5.1`, the script reports `HEAD is release tag: v0.5.1` and no release-ref warning.

---

## Add Bindings and Flutter Release Build Steps

Extend `scripts/build-macos.sh` so that after the checks it always runs `mopro build` at the repo root (no skip or opt-in flag), reports with a `git status`/`git diff --stat` notice if the committed bindings under `mopro_flutter_bindings/lib/src/rust/` changed, deletes only the Release `.app` under `flutter/build/macos/Build/Products/Release/` (never a full `flutter clean`, and no clean/incremental flag), and then runs `flutter build macos` inside `flutter/` with no `--build-name` override so the bundle version comes from the pubspec. Verification needs mopro-cli installed by hand first (`cargo install mopro-cli`), which the script itself never does; it is verified by running the script and confirming a freshly produced `Zero Knowledge Migration App.app` in the Release products directory whose `CFBundleShortVersionString` matches the pubspec version.

**Verified:**

- After the prerequisite, version and git-state checks, `scripts/build-macos.sh` always runs `mopro build` at the repo root (`build_bindings` is called unconditionally; the script has no skip, opt-in, clean or incremental flag -- `--help` is the only flag). It passes `--mode release --platforms flutter --no-auto-update` (matching `Config.toml`) because mopro-cli 0.3.7 otherwise prompts interactively for the build mode.
- Because mopro-cli exits 0 even when its build fails, the script also scans the `mopro build` output for `Failed to build project`: with a stub `mopro` that prints that message and exits 0, the script stops with `ERROR: mopro build failed (see its output above)` and exit 1 before touching the Release app.
- `mopro build` rewrites the `zkp_recovery_app` dependency's `path = "../.."` in `mopro_flutter_bindings/rust/Cargo.toml` to the machine's absolute repo path; the script puts the relative path back (`==> Restored the relative zkp_recovery_app path ...`), and after the run that file shows no diff from HEAD.
- When the committed bindings under `mopro_flutter_bindings/lib/src/rust/` change, the script prints a `WARNING: the committed bindings ... differ from HEAD` notice followed by `git status --short` and `git diff --stat` output for that directory (seen on the real run, where mopro's dart formatting changed six files); otherwise it prints that they are unchanged.
- Before `flutter build macos`, the script deletes only `flutter/build/macos/Build/Products/Release/Zero Knowledge Migration App.app` (logged as `Deleting the previous Release app`); it never runs `flutter clean` (the `Debug` products and build caches under `flutter/build/` remain).
- The script runs `flutter build macos --release` inside `flutter/` with no `--build-name` override, and stops non-zero if the build fails or does not produce the `.app`.
- With mopro-cli 0.3.7 installed by hand (`cargo install mopro-cli`; the script never installs it), a full run of `scripts/build-macos.sh` exits 0, printing only the expected 0.5.0/0.5.1 version-mismatch and git-state warnings plus the bindings notice, and produces a freshly built `flutter/build/macos/Build/Products/Release/Zero Knowledge Migration App.app` (timestamp from that run) whose `CFBundleShortVersionString` is `0.5.0`, matching `version: 0.5.0` in `flutter/pubspec.yaml`.
- `--help` documents the build steps in order (checks, `mopro build` with its flags and the path restore and bindings notice, Release `.app` deletion without `flutter clean`, `flutter build macos` with the version from the pubspec), and the script passes `bash -n` under Homebrew bash and `/bin/bash` 3.2.

---
