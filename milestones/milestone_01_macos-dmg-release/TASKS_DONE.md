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
