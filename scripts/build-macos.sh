#!/usr/bin/env bash
# Build the Zero Knowledge Migration App for Apple Silicon (arm64) macOS and package it as a dmg.
#
# Run from anywhere; the repo root is resolved from this script's own location.
# See --help for flags and prerequisites. Compatible with the macOS system bash (3.2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

PUBSPEC="$REPO_ROOT/flutter/pubspec.yaml"
ROOT_CARGO="$REPO_ROOT/Cargo.toml"
BINDINGS_CARGO="$REPO_ROOT/mopro_flutter_bindings/rust/Cargo.toml"

# `mopro build` settings (they match build_mode/target_platforms in the root Config.toml)
# and the committed Dart bindings it regenerates (relative to the repo root).
MOPRO_MODE="release"
MOPRO_PLATFORM="flutter"
BINDINGS_DART_REL="mopro_flutter_bindings/lib/src/rust"

# Bundle name comes from PRODUCT_NAME in flutter/macos/Runner/Configs/AppInfo.xcconfig.
APP_NAME="Zero Knowledge Migration App"
RELEASE_PRODUCTS_DIR="$REPO_ROOT/flutter/build/macos/Build/Products/Release"
APP_PATH="$RELEASE_PRODUCTS_DIR/$APP_NAME.app"

RUST_TARGET="aarch64-apple-darwin"

# Ad-hoc re-signing keeps the Release entitlements (app-sandbox, network.client); this file
# in git is the single source of truth for them.
ENTITLEMENTS="$REPO_ROOT/flutter/macos/Runner/Release.entitlements"

# The finished dmg and its .sha256 sidecar go to dist/ (git-ignored). The dmg file name is
# completed with the pubspec version once it has been read.
DIST_DIR="$REPO_ROOT/dist"
DMG_STEM="zkp-migration-app-macos-arm64"
VOLUME_NAME="$APP_NAME"

# Temporary dmg staging directory (the .app copy plus an /Applications symlink); the exit
# trap below deletes it, so a failed or interrupted run leaves no staging tree behind.
STAGING_DIR=""

usage() {
  cat <<EOF
Usage: scripts/$SCRIPT_NAME [-h|--help]

Build the Zero Knowledge Migration App for Apple Silicon (arm64) macOS on a developer
machine and package it as a distributable, ad-hoc signed dmg.

Flags:
  -h, --help    Show this help and exit.

The version is read from flutter/pubspec.yaml ("version:", without any +build suffix),
which is authoritative: bump it there before building a release.

Steps (always run in this order; there are no skip or clean/incremental flags):
  1. Check prerequisites, versions and git state.
  2. Run 'mopro build --mode $MOPRO_MODE --platforms $MOPRO_PLATFORM --no-auto-update' at
     the repo root to regenerate the Dart bindings, restore the relative crate path that
     mopro build rewrites in mopro_flutter_bindings/rust/Cargo.toml, and print a notice
     if the committed bindings under $BINDINGS_DART_REL/ changed.
  3. Delete only the Release app bundle
     (flutter/build/macos/Build/Products/Release/$APP_NAME.app);
     the build caches under flutter/build/ are kept, and 'flutter clean' is never run.
  4. Run 'flutter build macos' in flutter/ (no --build-name override, so the bundle
     version comes from flutter/pubspec.yaml).
  5. Ad-hoc re-sign the app: codesign --force --deep -s - with
     --entitlements flutter/macos/Runner/Release.entitlements (no Developer ID).
  6. Stage a copy of the app plus an /Applications symlink in a temporary directory
     (deleted on exit) and create a plain hdiutil dmg with the volume name
     "$VOLUME_NAME" at dist/$DMG_STEM-<version>.dmg
     (an existing dmg of the same name is overwritten).
  7. Print the dmg's SHA-256 and write it to dist/$DMG_STEM-<version>.dmg.sha256
     in 'shasum -a 256' format (hash, two spaces, bare file name); attach this sidecar to
     the GitHub release together with the dmg.

Prerequisites (checked before anything is built; a missing one stops the script with an
install hint -- the script never installs or changes your toolchain itself):
  - An Apple Silicon (arm64) macOS host
  - Xcode command-line tools (xcode-select --install)
  - flutter
  - CocoaPods (pod)
  - Rust via rustup (cargo, rustup) with the $RUST_TARGET target installed
      (rustup target add $RUST_TARGET)
  - hdiutil, codesign, shasum (macOS system tools)
  - mopro (cargo install mopro-cli)

Warnings (printed, but the script carries on):
  - the git working tree is dirty
  - HEAD is neither a release tag (v*) nor a release/* branch
  - the root Cargo.toml version, or the zkp_recovery_app dependency version in
    mopro_flutter_bindings/rust/Cargo.toml, differs from the flutter/pubspec.yaml version
EOF
}

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
error() { printf 'ERROR: %s\n' "$*" >&2; }
die() { error "$*"; exit 1; }

cleanup() {
  if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT
# Turn Ctrl-C and termination into a normal exit so the EXIT trap still cleans up.
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) error "unknown argument: $1"; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------------------
# Prerequisite checks (missing tools stop the script before anything is built)
# ---------------------------------------------------------------------------------------
MISSING=0

missing() {
  # $1 = what is missing, $2 = install hint
  error "$1 -- $2"
  MISSING=$((MISSING + 1))
}

have() { command -v "$1" >/dev/null 2>&1; }

check_host() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  if [ "$os" != "Darwin" ] || [ "$arch" != "arm64" ]; then
    die "this script must run on an Apple Silicon (arm64) macOS host (found $os/$arch)"
  fi
}

check_tools() {
  if ! have xcode-select || ! xcode-select -p >/dev/null 2>&1; then
    missing "Xcode command-line tools not found" "install them with: xcode-select --install"
  fi

  have flutter || missing "flutter not found on PATH" \
    "install Flutter (https://docs.flutter.dev/get-started/install/macos, or: brew install --cask flutter)"

  have pod || missing "CocoaPods (pod) not found on PATH" \
    "install it with: brew install cocoapods (or: sudo gem install cocoapods)"

  have cargo || missing "cargo not found on PATH" \
    "install Rust with rustup: https://rustup.rs"

  if have rustup; then
    if ! rustup target list --installed 2>/dev/null | grep -qx "$RUST_TARGET"; then
      missing "Rust target $RUST_TARGET is not installed" \
        "install it with: rustup target add $RUST_TARGET"
    fi
  else
    missing "rustup not found on PATH" "install Rust with rustup: https://rustup.rs"
  fi

  local tool
  for tool in hdiutil codesign shasum; do
    have "$tool" || missing "$tool not found on PATH" \
      "it ships with macOS; make sure /usr/bin is on PATH"
  done

  have mopro || missing "mopro not found on PATH" "install it with: cargo install mopro-cli"
}

# ---------------------------------------------------------------------------------------
# Version checks (mismatches only warn)
# ---------------------------------------------------------------------------------------

# pubspec "version:" value without quotes, whitespace or a +build suffix.
read_pubspec_version() {
  sed -n -E 's/^version:[[:space:]]*["'\'']?([^"'\''[:space:]#]+).*/\1/p' "$PUBSPEC" \
    | head -n 1 | sed 's/+.*//'
}

# `version = "..."` inside the given TOML table ($2, e.g. "package") of file $1.
read_toml_table_version() {
  awk -v table="[$2]" '
    /^[[:space:]]*\[/ {
      header = $0
      sub(/#.*/, "", header)
      gsub(/[[:space:]]/, "", header)
      in_table = (header == table)
      next
    }
    in_table && /^[[:space:]]*version[[:space:]]*=/ {
      line = $0
      sub(/^[^=]*=[[:space:]]*"/, "", line)
      sub(/".*/, "", line)
      print line
      exit
    }
  ' "$1"
}

check_versions() {
  VERSION="$(read_pubspec_version)"
  [ -n "$VERSION" ] || die "could not read the version: from ${PUBSPEC#"$REPO_ROOT"/}"
  info "Version (from flutter/pubspec.yaml): $VERSION"

  local root_version bindings_version
  root_version="$(read_toml_table_version "$ROOT_CARGO" package)"
  bindings_version="$(read_toml_table_version "$BINDINGS_CARGO" dependencies.zkp_recovery_app)"

  if [ "$root_version" != "$VERSION" ]; then
    warn "version mismatch: Cargo.toml [package] version is '${root_version:-<not found>}'," \
      "but flutter/pubspec.yaml version is '$VERSION' (the build uses $VERSION)"
  fi
  if [ "$bindings_version" != "$VERSION" ]; then
    warn "version mismatch: mopro_flutter_bindings/rust/Cargo.toml zkp_recovery_app dependency" \
      "version is '${bindings_version:-<not found>}', but flutter/pubspec.yaml version is" \
      "'$VERSION' (the build uses $VERSION)"
  fi
}

# ---------------------------------------------------------------------------------------
# Git state checks (only warn)
# ---------------------------------------------------------------------------------------
check_git_state() {
  if ! have git || ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    warn "git state not checked (git unavailable or $REPO_ROOT is not a git work tree)"
    return
  fi

  if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
    warn "the git working tree is dirty; a published release should be built from a clean tree"
  fi

  local branch tags
  branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  tags="$(git -C "$REPO_ROOT" tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]' || true)"
  if [ -n "$tags" ]; then
    info "HEAD is release tag: $(printf '%s' "$tags" | tr '\n' ' ')"
  elif [ "${branch#release/}" != "$branch" ]; then
    info "HEAD is release branch: $branch"
  else
    warn "HEAD (${branch:-detached at $(git -C "$REPO_ROOT" rev-parse --short HEAD)}) is neither" \
      "a release tag (v*) nor a release/* branch; a published release should be built from one"
  fi
}

# ---------------------------------------------------------------------------------------
# Build: Rust bindings (mopro build), then the Flutter Release app
# ---------------------------------------------------------------------------------------

# mopro build rewrites the committed `path = "../.."` of the zkp_recovery_app dependency in
# mopro_flutter_bindings/rust/Cargo.toml to this machine's absolute repo path; put the
# relative path back so the tree stays portable (both point at the same crate).
restore_bindings_crate_path() {
  local abs_line="path = \"$REPO_ROOT\"" tmp
  grep -qxF "$abs_line" "$BINDINGS_CARGO" || return 0
  tmp="$(mktemp -t build-macos-cargo)" || die "could not create a temporary file"
  awk -v abs="$abs_line" '$0 == abs { print "path = \"../..\""; next } { print }' \
    "$BINDINGS_CARGO" >"$tmp" && cat "$tmp" >"$BINDINGS_CARGO"
  rm -f "$tmp"
  info "Restored the relative zkp_recovery_app path in ${BINDINGS_CARGO#"$REPO_ROOT"/}"
}

# Always regenerate the Dart bindings from the current Rust API and circuit.
# The mode and platform are passed explicitly (matching Config.toml) because mopro-cli
# prompts for them interactively otherwise. mopro-cli exits 0 even when the build fails,
# so its output is also scanned for its failure message.
build_bindings() {
  info "Running mopro build at the repo root (mode: $MOPRO_MODE, platform: $MOPRO_PLATFORM)"
  local log status=0
  log="$(mktemp -t build-macos-mopro)" || die "could not create a temporary log file"
  (cd "$REPO_ROOT" && mopro build --mode "$MOPRO_MODE" --platforms "$MOPRO_PLATFORM" \
    --no-auto-update) 2>&1 | tee "$log" || status=$?
  if [ "$status" -ne 0 ] || grep -q "Failed to build project" "$log"; then
    rm -f "$log"
    die "mopro build failed (see its output above)"
  fi
  rm -f "$log"
  restore_bindings_crate_path

  if ! have git || ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    warn "cannot tell whether $BINDINGS_DART_REL/ changed (git unavailable)"
    return
  fi
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain -- "$BINDINGS_DART_REL" 2>/dev/null)" ]; then
    warn "the committed bindings under $BINDINGS_DART_REL/ differ from HEAD after mopro build;" \
      "review and commit them so the release matches the repo:"
    git -C "$REPO_ROOT" status --short -- "$BINDINGS_DART_REL" >&2 || true
    git -C "$REPO_ROOT" diff --stat -- "$BINDINGS_DART_REL" >&2 || true
  else
    info "Committed bindings under $BINDINGS_DART_REL/ are unchanged"
  fi
}

# Delete only the Release app bundle, so the app that gets signed and packaged is always
# freshly produced by this run (the Xcode, CocoaPods and cargokit caches are kept).
build_app() {
  if [ -e "$APP_PATH" ]; then
    info "Deleting the previous Release app: ${APP_PATH#"$REPO_ROOT"/}"
    rm -rf "$APP_PATH"
  fi

  info "Running flutter build macos in flutter/"
  (cd "$REPO_ROOT/flutter" && flutter build macos --release) || die "flutter build macos failed"

  [ -d "$APP_PATH" ] || die "flutter build macos did not produce ${APP_PATH#"$REPO_ROOT"/}"
  info "Built ${APP_PATH#"$REPO_ROOT"/}"
}

# ---------------------------------------------------------------------------------------
# Sign, package the dmg and write its checksum
# ---------------------------------------------------------------------------------------

# Ad-hoc re-sign the whole bundle, passing the Release entitlements explicitly so the
# re-sign never drops them.
sign_app() {
  [ -f "$ENTITLEMENTS" ] || die "entitlements file not found: ${ENTITLEMENTS#"$REPO_ROOT"/}"
  info "Ad-hoc signing ${APP_PATH#"$REPO_ROOT"/} with ${ENTITLEMENTS#"$REPO_ROOT"/}"
  codesign --force --deep -s - --entitlements "$ENTITLEMENTS" "$APP_PATH" \
    || die "codesign failed"
}

# Stage the app copy plus an /Applications symlink and turn that folder into a plain dmg.
create_dmg() {
  DMG_NAME="$DMG_STEM-$VERSION.dmg"
  DMG_PATH="$DIST_DIR/$DMG_NAME"

  STAGING_DIR="$(mktemp -d -t build-macos-dmg)" || die "could not create a staging directory"
  info "Staging the dmg contents in $STAGING_DIR"
  # ditto keeps the bundle's signature, symlinks and extended attributes intact.
  ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app" || die "could not copy the app to the staging directory"
  ln -s /Applications "$STAGING_DIR/Applications" || die "could not create the /Applications symlink"

  mkdir -p "$DIST_DIR" || die "could not create ${DIST_DIR#"$REPO_ROOT"/}/"
  # Silently replace a dmg (and its sidecar) of the same name from an earlier run.
  rm -f "$DMG_PATH" "$DMG_PATH.sha256"

  info "Creating ${DMG_PATH#"$REPO_ROOT"/} (volume name: $VOLUME_NAME)"
  hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -format UDZO -ov \
    "$DMG_PATH" || die "hdiutil create failed"
  [ -f "$DMG_PATH" ] || die "hdiutil create did not produce ${DMG_PATH#"$REPO_ROOT"/}"

  rm -rf "$STAGING_DIR"
  STAGING_DIR=""
}

# Print the dmg's SHA-256 and write the <dmg>.sha256 sidecar in standard `shasum -a 256`
# output format with the bare file name (run from dist/ so no directory is recorded).
write_checksum() {
  local line
  line="$(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME")" || die "shasum failed"
  printf '%s\n' "$line" >"$DMG_PATH.sha256" || die "could not write ${DMG_PATH#"$REPO_ROOT"/}.sha256"
  info "SHA-256 of $DMG_NAME:"
  printf '%s\n' "$line"
  info "Wrote ${DMG_PATH#"$REPO_ROOT"/}"
  info "Wrote ${DMG_PATH#"$REPO_ROOT"/}.sha256"
}

# ---------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------
info "Repo root: $REPO_ROOT"
info "Checking prerequisites"
check_host
check_tools
check_versions
check_git_state

if [ "$MISSING" -gt 0 ]; then
  die "$MISSING prerequisite(s) missing; install them (see the hints above) and re-run"
fi
info "All prerequisites found"

build_bindings
build_app
sign_app
create_dmg
write_checksum
