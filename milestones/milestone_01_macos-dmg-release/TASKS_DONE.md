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

## Sign, Package DMG and Write Checksum

Extend `scripts/build-macos.sh` to ad-hoc re-sign the built app with `codesign --force --deep -s -` passing `--entitlements flutter/macos/Runner/Release.entitlements`, stage a copy of the `.app` plus an `/Applications` symlink in a `mktemp -d` directory that an exit `trap` deletes, create a plain `hdiutil` dmg with the volume name `Zero Knowledge Migration App` as `dist/zkp-migration-app-macos-arm64-<version>.dmg` (silently overwriting an existing dmg of the same name), and print its SHA-256 while writing a `<dmg>.sha256` sidecar next to it in standard `shasum -a 256` output format with the bare file name and no directory; also add a `dist/` entry to the root `.gitignore`. Verified by running the script, mounting the dmg by hand to see the app and the `/Applications` symlink, comparing the sidecar with fresh `shasum -a 256` output, and confirming that no staging directory survives and that `git status` does not show `dist/`.

**Verified:**

- `scripts/build-macos.sh`, after `flutter build macos`, ad-hoc re-signs the built app with `codesign --force --deep -s - --entitlements flutter/macos/Runner/Release.entitlements` (`sign_app`); the real run logged `replacing existing signature`, and the mounted app copy shows exactly `com.apple.security.app-sandbox` and `com.apple.security.network.client` in `codesign -d --entitlements -` and passes `codesign --verify --deep --strict`.
- The script stages a `ditto` copy of `Zero Knowledge Migration App.app` plus an `Applications -> /Applications` symlink in a `mktemp -d -t build-macos-dmg` directory, and an `EXIT` trap (with `INT`/`TERM` turned into exits) deletes it: no `$TMPDIR/build-macos-dmg*` directory survives the successful full run, and none survives a run in which a stub `hdiutil` failed (that run stopped with `ERROR: hdiutil create failed`, exit 1).
- It creates a plain `hdiutil create -volname "Zero Knowledge Migration App" -srcfolder <staging> -format UDZO -ov` dmg at `dist/zkp-migration-app-macos-arm64-0.5.0.dmg` (version from `flutter/pubspec.yaml`); `hdiutil imageinfo` reports `Format: UDZO` and the mounted volume name is `Zero Knowledge Migration App`.
- An existing dmg of the same name is silently overwritten: a repeat sign/dmg/checksum run replaced the dmg (new mtime and hash) with no prompt, error or warning, and exited 0.
- It prints the dmg's SHA-256 and writes `dist/zkp-migration-app-macos-arm64-0.5.0.dmg.sha256` in standard `shasum -a 256` format (`<hash>  zkp-migration-app-macos-arm64-0.5.0.dmg`, bare file name, no directory); the sidecar is byte-identical to fresh `shasum -a 256` output run in `dist/`, and `shasum -a 256 -c` reports `OK`.
- The full `scripts/build-macos.sh` run (mopro-cli 0.3.7 installed by hand) exits 0, printing only the expected 0.5.0/0.5.1 version-mismatch, git-state and bindings-changed warnings.
- Mounting the dmg by hand (`hdiutil attach -readonly -nobrowse`) shows `Zero Knowledge Migration App.app` and an `Applications` symlink whose `readlink` is `/Applications`.
- The root `.gitignore` has a `dist/` entry (`git check-ignore -v dist/` matches `.gitignore:4:dist/`) and `git status` does not show `dist/`.
- `--help` lists the new steps 5 to 7 (ad-hoc re-sign with the Release entitlements, staging plus `hdiutil` dmg with the volume name and file name and silent overwrite, SHA-256 print plus sidecar), and the script passes `bash -n` under Homebrew bash and `/bin/bash` 3.2.

---

## Add Post-Build Signature and DMG Verification

Extend `scripts/build-macos.sh` with a final layered check stage in which any failure stops it with a non-zero exit: `codesign --verify --deep --strict --verbose=2` on the built app, a comparison of the `codesign -d --entitlements -` output against the expected set in `flutter/macos/Runner/Release.entitlements`, `hdiutil verify` on the finished dmg, a read-only, no-browse test mount (`hdiutil attach -readonly -nobrowse`, detached by a trap) that confirms the `.app` and the `/Applications` symlink are present and re-runs `codesign --verify` on the mounted copy, and lastly `spctl --assess --type execute`, whose expected rejection of the ad-hoc signature is printed as information only and never changes the exit status. No bundle-content assertions (`lipo` architecture, `CFBundleIdentifier`, `CFBundleShortVersionString`) are added. Verified by a full script run passing, and by a deliberate tamper (for example re-signing the app without entitlements, or appending a byte to the dmg) making the script exit non-zero.

**Verified:**

- `scripts/build-macos.sh` ends with a final verification stage (`verify_all`, run after `write_checksum`) whose checks run in order and each stop the script with a non-zero exit (`ERROR: verification failed: ...; do not publish dist/<dmg> or its .sha256`, exit 1) on failure.
- It runs `codesign --verify --deep --strict --verbose=2` on the built Release app; an app whose sealed resource was modified after signing is rejected (`a sealed resource is missing or invalid`, exit 1).
- It compares the `codesign -d --entitlements - --xml` output of the built app with `flutter/macos/Runner/Release.entitlements`, both normalised by `plutil -convert xml1` (sorted keys); an app re-signed without entitlements (`the signed app has no entitlements`) and one signed with an extra `network.server` entitlement (diff shown) both exit 1.
- It runs `hdiutil verify` on the finished dmg; a dmg with one byte appended is rejected (`image not recognized`, exit 1).
- It test-mounts the dmg with `hdiutil attach -readonly -nobrowse -noautoopen -mountpoint <mktemp -d dir>`, checks that `Zero Knowledge Migration App.app` and an `Applications` symlink whose `readlink` is `/Applications` are present, and re-runs `codesign --verify --deep --strict --verbose=2` on the mounted copy; a dmg without the symlink and a dmg holding a tampered app copy each exit 1. The EXIT trap detaches the image (falling back to `-force`) and removes the mount point: after the passing and all failing runs, `hdiutil info` lists no attached image and no `$TMPDIR/build-macos-*` directory survives.
- `spctl --assess --type execute --verbose=2` runs last on the built app; its rejection (`rejected`, exit 3) is printed as information only and the script still exits 0 (a missing `spctl` is also only reported).
- No bundle-content assertions were added: the script contains no `lipo`, `CFBundleIdentifier` or `CFBundleShortVersionString` check.
- A full real run of `scripts/build-macos.sh` (mopro build, flutter build, sign, dmg, checksum, verification) exits 0, printing only the expected 0.5.0/0.5.1 version-mismatch, git-state and bindings-changed warnings, `All signature and dmg checks passed`, and the informational spctl rejection.
- Deliberate tampers through the full script make it exit non-zero: re-signing the app without `--entitlements` (stub `codesign` on PATH) exits 1 at the entitlements comparison, and appending a byte to the dmg after `hdiutil create` (stub `hdiutil` on PATH) exits 1 at `hdiutil verify`.
- `--help` documents the new step 8 (the checks in order, the informational spctl result and not publishing on failure), and the script passes `bash -n` under Homebrew bash and `/bin/bash` 3.2.

---
