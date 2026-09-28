# ZKP Migration on macOS (Apple Silicon).

This guide gives step-by-step instructions for downloading, verifying, installing and running the ZKP recovery app on macOS. The macOS app is built for Apple Silicon (M-series) Macs only and needs macOS 12 or later. It is not available for Intel Macs.

## Step 1: Download and Verify the Disk Image

Visit the official Github [releases](https://github.com/Zilliqa/zkp_recovery_app/releases) page and download the macOS disk image for the latest version, named `zkp-migration-app-macos-arm64-<version>.dmg` (for example `zkp-migration-app-macos-arm64-0.5.0.dmg`).
**DO NOT DOWNLOAD** the application from any other source.

1. Open the Terminal app (Applications → Utilities → Terminal) and go to the folder the disk image was saved to, usually Downloads:
   ```bash
   $ cd ~/Downloads
   ```
2. Compute the checksum of the disk image, replacing `<version>` with the version you downloaded:
   ```bash
   $ shasum -a 256 zkp-migration-app-macos-arm64-<version>.dmg
   ```
   The output is the checksum followed by the file name:
   ```text
   <64 hexadecimal characters>  zkp-migration-app-macos-arm64-<version>.dmg
   ```
3. Compare the checksum value by eye against the official one published for the same release. It is listed on the release page, and it is also attached to the release as the `zkp-migration-app-macos-arm64-<version>.dmg.sha256` file, which you can open in any text editor. Every character must match.

## Step 2: Install the Application

**DO NOT PROCEED** if the checksum value computed above does not match the official checksum, as it indicates that the application may have been tampered with.

1. Open the disk image only if the checksum matches, by double-clicking it in Finder or from the Terminal:
   ```bash
   $ open zkp-migration-app-macos-arm64-<version>.dmg
   ```
   A window opens showing the mounted volume, `/Volumes/Zero Knowledge Migration App`, which contains `Zero Knowledge Migration App` and a shortcut to the `Applications` folder.
2. Drag `Zero Knowledge Migration App` onto the `Applications` shortcut in that window. This copies the app to `/Applications`.
3. Eject the disk image by clicking the eject button next to `Zero Knowledge Migration App` in the Finder sidebar, or from the Terminal:
   ```bash
   $ hdiutil detach "/Volumes/Zero Knowledge Migration App"
   ```
   Always start the app from `/Applications`, not from the disk image.

## Step 3: Run the Application and Allow It Through Gatekeeper

The app is ad-hoc signed. It is not signed with an Apple Developer ID and it is not notarized by Apple, so the first time you open it, macOS Gatekeeper blocks it and shows a warning. This is expected for this app. Only allow an app through Gatekeeper that you downloaded from the official releases page and whose checksum matched in Step 1.

### Main method: Open Anyway

1. Open `Zero Knowledge Migration App` from the `Applications` folder. macOS blocks it and shows a warning (see [Gatekeeper messages](#gatekeeper-messages) below). Close the warning with "Done" or "OK". Do not choose "Move to Trash".
2. Open System Settings → Privacy & Security. On macOS 12 this is System Preferences → Security & Privacy (General tab).
3. Scroll down to the Security section, where a note says that "Zero Knowledge Migration App" was blocked, and click "Open Anyway".
4. Confirm by clicking "Open" (or "Open Anyway") in the dialog that follows, and enter your password or use Touch ID if asked.
5. You should see the GUI application start up. From now on it opens normally, with no warning.

### Fallback method: remove the quarantine attribute

Use this if macOS says the app "is damaged and can't be opened", or if the "Open Anyway" button does not appear. macOS marks every downloaded file with a quarantine attribute, and removing it from the installed app stops Gatekeeper from checking it. The quotes around the path are needed because the app name contains spaces.

1. Run in the Terminal:
   ```bash
   $ xattr -dr com.apple.quarantine "/Applications/Zero Knowledge Migration App.app"
   ```
2. Open `Zero Knowledge Migration App` from the `Applications` folder again. You should see the GUI application start up.

### Gatekeeper messages

These messages appear because the app is ad-hoc signed rather than signed with an Apple Developer ID and notarized, so macOS cannot confirm who published it. They do not mean that anything is wrong with a copy whose checksum matched. Match the message you see to its fix:

| Message | Fix |
| --- | --- |
| Apple could not verify “Zero Knowledge Migration App” is free of malware that may harm your Mac or compromise your privacy. | [Open Anyway](#main-method-open-anyway) |
| “Zero Knowledge Migration App” can’t be opened because it is from an unidentified developer. | [Open Anyway](#main-method-open-anyway) |
| “Zero Knowledge Migration App” is damaged and can’t be opened. You should move it to the Trash. | [Remove the quarantine attribute](#fallback-method-remove-the-quarantine-attribute) with the `xattr` command |


## (Alternative): Build from Source / Release

These steps are for maintainers who build the macOS disk image themselves, for example to publish a release. They need an Apple Silicon (arm64) Mac. The build script `scripts/build-macos.sh` checks the prerequisites below before building anything. It stops with an install hint if one is missing, and it never installs or changes your toolchain itself. Run `scripts/build-macos.sh --help` for its built-in reference. Its only flag is `-h, --help`.

1. Download the source from [Github](https://github.com/Zilliqa/zkp_recovery_app)
   ```bash
   $ git clone https://github.com/Zilliqa/zkp_recovery_app.git
   $ cd zkp_recovery_app
   ```

2. Install the toolchain:
   - The Xcode command-line tools:
     ```bash
     $ xcode-select --install
     ```
   - [Flutter](https://docs.flutter.dev/get-started/install/macos), for example with `brew install --cask flutter`.
   - CocoaPods, for example with `brew install cocoapods` (or `sudo gem install cocoapods`).
   - Rust via [rustup](https://rustup.rs), with the Apple Silicon target:
     ```bash
     $ rustup target add aarch64-apple-darwin
     ```
   - [Mopro](../README.md) (the mopro-cli), which the script needs for `mopro build`:
     ```bash
     $ cargo install mopro-cli
     ```
   - `hdiutil`, `codesign` and `shasum` are part of macOS and need no installation.

3. For a release, bump the version first, on the `release/vX.Y.Z` branch before it is merged and tagged. `flutter/pubspec.yaml` is the authoritative version: its `version:` (without any `+build` suffix) gives the dmg file name and the app's bundle version. Also update the root `Cargo.toml` version and the matching `zkp_recovery_app` dependency version in `mopro_flutter_bindings/rust/Cargo.toml`. The script only warns, and carries on, if these differ from the pubspec. Then build from a clean checkout of the release tag (or the `release/*` branch). The script also only warns if the working tree is dirty or if HEAD is neither a release tag (`v*`) nor a `release/*` branch.
   ```bash
   $ git checkout v<version>
   ```

4. Build, sign and package the disk image from the repo root:
   ```bash
   $ scripts/build-macos.sh
   ```
   The script runs `mopro build`, then `flutter build macos`. It ad-hoc signs the app with the entitlements in `flutter/macos/Runner/Release.entitlements` and creates the disk image `dist/zkp-migration-app-macos-arm64-<version>.dmg`. It prints the image's SHA-256 checksum and writes it to `dist/zkp-migration-app-macos-arm64-<version>.dmg.sha256`. Finally it verifies the signature, the entitlements and the disk image. The `spctl` rejection it prints at the end is expected for an ad-hoc signed app and is only informational. If the script exits with an error, **DO NOT PUBLISH** the disk image or its checksum file.

5. Publish the release: on the official Github [releases](https://github.com/Zilliqa/zkp_recovery_app/releases) page, attach both `dist/zkp-migration-app-macos-arm64-<version>.dmg` and its `dist/zkp-migration-app-macos-arm64-<version>.dmg.sha256` sidecar to the release. The sidecar holds the checksum exactly as the build computed it, and users compare against it as described in Step 1, so do not retype the checksum by hand.
