# Milestone 1: macOS DMG Release

## Goal

Add a developer-machine build script that turns the Flutter app into a distributable Apple Silicon (arm64) macOS app. It checks the prerequisites, runs `mopro build` and `flutter build macos`, ad-hoc signs the app (`codesign --force --deep -s -`, no Developer ID), and packages it as a plain `hdiutil` `.dmg` with an `/Applications` shortcut. The dmg's file name includes the version, and the script prints its SHA-256. It checks the signature and dmg, and it warns (without stopping) if the versions in `Cargo.toml`, `pubspec.yaml` and the bindings disagree. Alongside the script, document how a maintainer uses it and add a user guide, `docs/macOS.md`, in the style of `docs/Linux.md`: download, check the checksum, install from the dmg, and get past Gatekeeper for an unsigned app. The milestone is done when a dry run of build → sign → create dmg succeeds on the developer machine, with any problems it finds fixed. Launch and the in-app flow will be tested manually afterwards.

Out of scope: Intel/universal builds, Developer ID signing and notarization, a styled dmg (create-dmg), automated launch or end-to-end testing, and fixing the current 0.5.0/v0.5.1 version mismatch.

## Relevant starting state

### Existing build and release tooling

The repo has no app build or packaging script for any platform. Releases so far have been built by hand on a developer machine. `docs/Linux.md` describes a release `.tar.gz` named `zkp-migration-app-linux-amd64.tar.gz`, whose checksum users compare against the one listed on the GitHub releases page. There is no `.github/workflows` directory. The only existing shell scripts are in `groth16-prover-min/`, `plonk-*`, `groth16-cli-ceremony/`, `claim-relayer/e2e-anvil/` and cargokit's `build_pod.sh`, so there is no repo-level `scripts/` convention yet.

### Rust bindings and how they get built on macOS

`mopro build` (driven by the root `Config.toml`: release mode, `circom` adapter, `flutter` platform) regenerates the Dart bindings in `mopro_flutter_bindings/lib/src/rust/`, which are committed to git. The native Rust library is compiled during `flutter build macos` by the `mopro_flutter_bindings` pod's "Build Rust library" script phase, which runs `cargokit/build_pod.sh ../rust mopro_flutter_bindings` and force-loads `libmopro_flutter_bindings.a`. `build.rs` transpiles `test-vectors/circom/groth.wasm`, which is committed. `test-vectors/circom/groth_final.zkey` is absent; only `cargo test` needs it, not the build. The app downloads its zkey at runtime.

### Versions

The root `Cargo.toml` is at `0.5.1`, and so is the `zkp_recovery_app` dependency version in `mopro_flutter_bindings/rust/Cargo.toml`. `flutter/pubspec.yaml` is at `version: 0.5.0`, even though the latest tag is `v0.5.1`. `mopro_flutter_bindings/pubspec.yaml` has its own unrelated `0.0.1`. The macOS `Info.plist` takes `CFBundleShortVersionString` and `CFBundleVersion` from `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER`, which means from the pubspec.

### macOS Flutter project (`flutter/macos/`)

`AppInfo.xcconfig` sets `PRODUCT_NAME = Zero Knowledge Migration App` and `PRODUCT_BUNDLE_IDENTIFIER = com.zilliqa.zkpRecoveryApp`, so the bundle is `Zero Knowledge Migration App.app` (the name has spaces). The deployment target is macOS 12.0 in both the Podfile and the Xcode project. Xcode signing is already `CODE_SIGN_IDENTITY = "-"` (ad-hoc), with no `DEVELOPMENT_TEAM` and no hardened-runtime setting. `Release.entitlements` turns on `app-sandbox` and `network.client`. `DebugProfile.entitlements` also adds `allow-jit` and `network.server`. Re-signing with `codesign --force --deep -s -` without `--entitlements` would drop these entitlements. Only a `Debug` build exists under `flutter/build/macos/Build/Products/`, so a Release macOS build has not been produced on this machine yet.

### Runtime behaviour relevant to a sandboxed release

A release build (`!kDebugMode`) uses `domain` `32769` (zq2 mainnet); see `flutter/lib/services/proof_service.dart:116`. `DownloadService` stores the ~358 MB proving key in `getApplicationSupportDirectory()`. Under the sandbox, that directory is inside `~/Library/Containers/com.zilliqa.zkpRecoveryApp/`. The download uses `package:http` over HTTPS to GCS, which is covered by `network.client`.

### Developer machine toolchain (as found)

The machine runs macOS 26.6.2 on arm64, with Xcode 27.0, Flutter 3.47.2 (stable, Homebrew), CocoaPods (Homebrew), and rustup/cargo with the `aarch64-apple-darwin` target installed. `hdiutil`, `codesign` and `shasum` are system tools. `mopro` (the mopro-cli) is **not** installed or on `PATH`, so the `mopro build` step needs `cargo install mopro-cli` before the dry run.

### User documentation

`docs/Linux.md` and `docs/Windows.md` each have a screenshot (`docs/linux.png`, `docs/windows.png`). The Linux guide is structured as: download from GitHub releases only → check the SHA-256 → unpack and run → "(Alternative): Build from Source". There is no `docs/macOS.md`, and no macOS screenshot. The root `README.md` is the stock mopro template and does not link to the platform guides.

## Decisions

### Build script location and name

The macOS build script lives at `scripts/build-macos.sh`, in a new top-level `scripts/` directory. It resolves the repo root from its own location, runs `mopro build` at the root and `flutter build macos` inside `flutter/`, and reads the three version files from there. The `scripts/` directory is the repo-level home for platform packaging scripts, so any future Linux or Windows packaging scripts follow the same `scripts/build-<platform>.sh` pattern.

### DMG output location

The script writes the finished `.dmg` to a new `dist/` directory at the repo root, and a `dist/` entry is added to the root `.gitignore`, because nothing ignores it today. Keeping it there separates the release artifact from build state, so `flutter clean` or wiping `flutter/build/` never deletes it. The dmg staging folder (the `.app` copy and the `/Applications` symlink) is built in a `mktemp -d` directory that an exit `trap` deletes, so a failed run leaves no staging tree behind. An existing dmg with the same name is silently overwritten, so the build, sign and dmg dry run can be repeated until it passes. Releases are built from a tag, which guards against a rebuilt dmg replacing one whose checksum was already published.

### Version source for naming

`flutter/pubspec.yaml` is the authoritative version. The script reads its `version:` (without any `+build` suffix) and uses it in the dmg file name. It runs `flutter build macos` with no `--build-name` override, so the bundle's `CFBundleShortVersionString` comes from the pubspec through `FLUTTER_BUILD_NAME`, and the file name and bundle version always match. If the root `Cargo.toml` version or the `zkp_recovery_app` dependency version in `mopro_flutter_bindings/rust/Cargo.toml` differs from the pubspec, the script prints a warning naming each file and value and carries on. As long as the 0.5.0/0.5.1 mismatch stays unfixed (it is out of scope here), a build from the current tree is named and versioned 0.5.0. A maintainer must bump the pubspec before building a release.

### Artifact and volume naming

The dmg file is named `zkp-migration-app-macos-arm64-<version>.dmg`. It follows the Linux `zkp-migration-app-linux-amd64.tar.gz` stem with the macOS platform and arch, and puts the pubspec version last. The name is lowercase, hyphenated and has no spaces, so the `shasum -a 256` step in `docs/macOS.md` and the script need no quoting. The mounted volume is named after the bundle's product name, `Zero Knowledge Migration App`, with no version, to match the `.app` users drag to `/Applications`. Any script or doc step that refers to the mounted volume uses `/Volumes/Zero Knowledge Migration App`, quoted. Renaming the unversioned Linux artifact is not part of this milestone.

### Entitlements when re-signing

The script keeps the goal's ad-hoc re-sign step (`codesign --force --deep -s -`) and passes the entitlements explicitly with `--entitlements flutter/macos/Runner/Release.entitlements`. The shipped app stays sandboxed with `app-sandbox` and `network.client`, the same configuration Xcode applies to the Release build, so the app that handles mnemonics stays isolated. `Release.entitlements` in git remains the single source of truth for the app's entitlements, and the script never drops them or substitutes its own. The zkey therefore keeps its home under `~/Library/Containers/com.zilliqa.zkpRecoveryApp/`, and the sandboxed Release behaviour (zkey download and file access) has to be confirmed at runtime during the manual testing.

## Out of Scope

