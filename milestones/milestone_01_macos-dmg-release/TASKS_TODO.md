# TASKS TODO

## Write macOS User Guide

Add a text-only `docs/macOS.md` in the style of `docs/Linux.md` (no screenshot, no image reference, and no link to it added to any other doc) that covers: downloading `zkp-migration-app-macos-arm64-<version>.dmg` only from the official GitHub releases page; checking it with `shasum -a 256 <dmg>` and comparing the output by eye with the published hash from the release page or the `.sha256` asset (not `shasum -c`); installing by opening the dmg and dragging the app from `/Volumes/Zero Knowledge Migration App` to `/Applications`; and getting past Gatekeeper, leading with Open Anyway (launch once, then System Settings → Privacy & Security, or System Preferences → Security & Privacy on macOS 12) and falling back to `xattr -dr com.apple.quarantine "/Applications/Zero Knowledge Migration App.app"`, with a short section matching each message to its fix ("Apple could not verify … is free of malware" or "unidentified developer" → Open Anyway; "… is damaged and can't be opened" → the xattr command) and explaining that the messages appear because the app is ad-hoc signed and not Developer ID signed or notarized. Verified by reading the finished guide against these decisions and checking it uses no right-click → Open shortcut and no per-version procedures.

---

## Add Maintainer Build Section to macOS Guide

Append an "(Alternative): Build from Source / Release" section to the end of `docs/macOS.md`, mirroring the end of `docs/Linux.md`, that walks a maintainer through cloning the repo, installing the toolchain (including `cargo install mopro-cli`), bumping `flutter/pubspec.yaml` as the authoritative version before a release, running `scripts/build-macos.sh`, and publishing the dmg together with its `.sha256` sidecar on the GitHub release; no separate maintainer document is added. Verified by checking that the section's flags and prerequisites agree with the script's `--help` output.

---

## Run Build Sign and DMG Dry Run

On the developer machine, with mopro-cli installed by hand (`cargo install mopro-cli`) because the script never installs tools, run `scripts/build-macos.sh` end to end on the current feature branch and fix in the script any problem the run surfaces (updating the `--help` text and the `docs/macOS.md` maintainer section together with any flag or prerequisite change) until build → sign → create dmg and all verification checks pass. Verified by the script exiting zero with `dist/zkp-migration-app-macos-arm64-0.5.0.dmg` and its `.sha256` sidecar present and only the expected version-mismatch and git-state warnings printed; launching the app and the in-app flow are left for manual testing afterwards.

---
