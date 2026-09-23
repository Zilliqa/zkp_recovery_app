# Milestone 1: macOS DMG Release

## Goal

Add a developer-machine build script that turns the Flutter app into a distributable Apple Silicon (arm64) macOS app. It checks the prerequisites, runs `mopro build` and `flutter build macos`, ad-hoc signs the app (`codesign --force --deep -s -`, no Developer ID), and packages it as a plain `hdiutil` `.dmg` with an `/Applications` shortcut. The dmg's file name includes the version, and the script prints its SHA-256. It checks the signature and dmg, and it warns (without stopping) if the versions in `Cargo.toml`, `pubspec.yaml` and the bindings disagree. Alongside the script, document how a maintainer uses it and add a user guide, `docs/macOS.md`, in the style of `docs/Linux.md`: download, check the checksum, install from the dmg, and get past Gatekeeper for an unsigned app. The milestone is done when a dry run of build → sign → create dmg succeeds on the developer machine, with any problems it finds fixed. Launch and the in-app flow will be tested manually afterwards.

Out of scope: Intel/universal builds, Developer ID signing and notarization, a styled dmg (create-dmg), automated launch or end-to-end testing, and fixing the current 0.5.0/v0.5.1 version mismatch.

## Relevant starting state

## Decisions

## Out of Scope

