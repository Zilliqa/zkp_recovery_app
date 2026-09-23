# TASKS TODO

## Run Build Sign and DMG Dry Run

On the developer machine, with mopro-cli installed by hand (`cargo install mopro-cli`) because the script never installs tools, run `scripts/build-macos.sh` end to end on the current feature branch and fix in the script any problem the run surfaces (updating the `--help` text and the `docs/macOS.md` maintainer section together with any flag or prerequisite change) until build → sign → create dmg and all verification checks pass. Verified by the script exiting zero with `dist/zkp-migration-app-macos-arm64-0.5.0.dmg` and its `.sha256` sidecar present and only the expected version-mismatch and git-state warnings printed; launching the app and the in-app flow are left for manual testing afterwards.

---
