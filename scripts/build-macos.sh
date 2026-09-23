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

RUST_TARGET="aarch64-apple-darwin"

usage() {
  cat <<EOF
Usage: scripts/$SCRIPT_NAME [-h|--help]

Build the Zero Knowledge Migration App for Apple Silicon (arm64) macOS on a developer
machine and package it as a distributable, ad-hoc signed dmg.

Flags:
  -h, --help    Show this help and exit.

The version is read from flutter/pubspec.yaml ("version:", without any +build suffix),
which is authoritative: bump it there before building a release.

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
