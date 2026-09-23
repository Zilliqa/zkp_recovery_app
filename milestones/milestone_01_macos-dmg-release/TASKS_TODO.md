# TASKS TODO

## Add Maintainer Build Section to macOS Guide

Append an "(Alternative): Build from Source / Release" section to the end of `docs/macOS.md`, mirroring the end of `docs/Linux.md`, that walks a maintainer through cloning the repo, installing the toolchain (including `cargo install mopro-cli`), bumping `flutter/pubspec.yaml` as the authoritative version before a release, running `scripts/build-macos.sh`, and publishing the dmg together with its `.sha256` sidecar on the GitHub release; no separate maintainer document is added. Verified by checking that the section's flags and prerequisites agree with the script's `--help` output.

---

## Run Build Sign and DMG Dry Run

On the developer machine, with mopro-cli installed by hand (`cargo install mopro-cli`) because the script never installs tools, run `scripts/build-macos.sh` end to end on the current feature branch and fix in the script any problem the run surfaces (updating the `--help` text and the `docs/macOS.md` maintainer section together with any flag or prerequisite change) until build → sign → create dmg and all verification checks pass. Verified by the script exiting zero with `dist/zkp-migration-app-macos-arm64-0.5.0.dmg` and its `.sha256` sidecar present and only the expected version-mismatch and git-state warnings printed; launching the app and the in-app flow are left for manual testing afterwards.

---
