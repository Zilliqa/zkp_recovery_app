# TASKS TODO

## Add Bindings and Flutter Release Build Steps

Extend `scripts/build-macos.sh` so that after the checks it always runs `mopro build` at the repo root (no skip or opt-in flag), reports with a `git status`/`git diff --stat` notice if the committed bindings under `mopro_flutter_bindings/lib/src/rust/` changed, deletes only the Release `.app` under `flutter/build/macos/Build/Products/Release/` (never a full `flutter clean`, and no clean/incremental flag), and then runs `flutter build macos` inside `flutter/` with no `--build-name` override so the bundle version comes from the pubspec. Verification needs mopro-cli installed by hand first (`cargo install mopro-cli`), which the script itself never does; it is verified by running the script and confirming a freshly produced `Zero Knowledge Migration App.app` in the Release products directory whose `CFBundleShortVersionString` matches the pubspec version.

---

## Sign, Package DMG and Write Checksum

Extend `scripts/build-macos.sh` to ad-hoc re-sign the built app with `codesign --force --deep -s -` passing `--entitlements flutter/macos/Runner/Release.entitlements`, stage a copy of the `.app` plus an `/Applications` symlink in a `mktemp -d` directory that an exit `trap` deletes, create a plain `hdiutil` dmg with the volume name `Zero Knowledge Migration App` as `dist/zkp-migration-app-macos-arm64-<version>.dmg` (silently overwriting an existing dmg of the same name), and print its SHA-256 while writing a `<dmg>.sha256` sidecar next to it in standard `shasum -a 256` output format with the bare file name and no directory; also add a `dist/` entry to the root `.gitignore`. Verified by running the script, mounting the dmg by hand to see the app and the `/Applications` symlink, comparing the sidecar with fresh `shasum -a 256` output, and confirming that no staging directory survives and that `git status` does not show `dist/`.

---

## Add Post-Build Signature and DMG Verification

Extend `scripts/build-macos.sh` with a final layered check stage in which any failure stops it with a non-zero exit: `codesign --verify --deep --strict --verbose=2` on the built app, a comparison of the `codesign -d --entitlements -` output against the expected set in `flutter/macos/Runner/Release.entitlements`, `hdiutil verify` on the finished dmg, a read-only, no-browse test mount (`hdiutil attach -readonly -nobrowse`, detached by a trap) that confirms the `.app` and the `/Applications` symlink are present and re-runs `codesign --verify` on the mounted copy, and lastly `spctl --assess --type execute`, whose expected rejection of the ad-hoc signature is printed as information only and never changes the exit status. No bundle-content assertions (`lipo` architecture, `CFBundleIdentifier`, `CFBundleShortVersionString`) are added. Verified by a full script run passing, and by a deliberate tamper (for example re-signing the app without entitlements, or appending a byte to the dmg) making the script exit non-zero.

---

## Write macOS User Guide

Add a text-only `docs/macOS.md` in the style of `docs/Linux.md` (no screenshot, no image reference, and no link to it added to any other doc) that covers: downloading `zkp-migration-app-macos-arm64-<version>.dmg` only from the official GitHub releases page; checking it with `shasum -a 256 <dmg>` and comparing the output by eye with the published hash from the release page or the `.sha256` asset (not `shasum -c`); installing by opening the dmg and dragging the app from `/Volumes/Zero Knowledge Migration App` to `/Applications`; and getting past Gatekeeper, leading with Open Anyway (launch once, then System Settings → Privacy & Security, or System Preferences → Security & Privacy on macOS 12) and falling back to `xattr -dr com.apple.quarantine "/Applications/Zero Knowledge Migration App.app"`, with a short section matching each message to its fix ("Apple could not verify … is free of malware" or "unidentified developer" → Open Anyway; "… is damaged and can't be opened" → the xattr command) and explaining that the messages appear because the app is ad-hoc signed and not Developer ID signed or notarized. Verified by reading the finished guide against these decisions and checking it uses no right-click → Open shortcut and no per-version procedures.

---

## Add Maintainer Build Section to macOS Guide

Append an "(Alternative): Build from Source / Release" section to the end of `docs/macOS.md`, mirroring the end of `docs/Linux.md`, that walks a maintainer through cloning the repo, installing the toolchain (including `cargo install mopro-cli`), bumping `flutter/pubspec.yaml` as the authoritative version before a release, running `scripts/build-macos.sh`, and publishing the dmg together with its `.sha256` sidecar on the GitHub release; no separate maintainer document is added. Verified by checking that the section's flags and prerequisites agree with the script's `--help` output.

---

## Run Build Sign and DMG Dry Run

On the developer machine, with mopro-cli installed by hand (`cargo install mopro-cli`) because the script never installs tools, run `scripts/build-macos.sh` end to end on the current feature branch and fix in the script any problem the run surfaces (updating the `--help` text and the `docs/macOS.md` maintainer section together with any flag or prerequisite change) until build → sign → create dmg and all verification checks pass. Verified by the script exiting zero with `dist/zkp-migration-app-macos-arm64-0.5.0.dmg` and its `.sha256` sidecar present and only the expected version-mismatch and git-state warnings printed; launching the app and the in-app flow are left for manual testing afterwards.

---
