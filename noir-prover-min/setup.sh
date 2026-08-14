#!/usr/bin/env bash
# One-time: fetch the one dependency that has no git tag (sha512) at its pinned commit.
# The tagged deps (bignum, noir_bigcurve, sha256) are fetched automatically by nargo.
set -e
cd "$(dirname "$0")"
if [ ! -d vendor/sha512 ]; then
  mkdir -p vendor
  git clone -q https://github.com/noir-lang/sha512 vendor/sha512
  ( cd vendor/sha512 && git checkout -q e92ffb473f3264529a0793770f63a09946df50cc )
  echo "vendored sha512 @ e92ffb4"
fi
