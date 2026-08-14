#!/usr/bin/env bash
# Produce the bundled SRS asset (flutter/assets/srs_g1.srs) so `flutter build` bakes it in and
# the Noir path proves OFFLINE (no ~128 MB SRS download on every launch).
#
# Two steps: download the raw G1 SRS prefix (.dat) from crs.aztec.network, then convert it to the
# bincode `.srs` format the app bundles (same format mopro's example ships) via `gen_srs`.
#
# The output is gitignored (~140 MB > GitHub's 100 MB per-file limit — same reason the Groth16
# zkey lives on GCS, not in the repo). Run this once before building for offline use, then
# uncomment the `- assets/srs_g1.srs` line in flutter/pubspec.yaml.
#
# Size: noir-rs needs circuit_size * ULTRA_HONK_SRS_MULTIPLIER(8) + 1 points, 64 bytes each. The
# current circuit (262,144) needs ~128 MiB; we grab a margin. Bump POINTS if you enlarge the
# circuit (too few points makes noir-rs panic). Over-fetching is harmless (the loader reads only
# what it needs).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"

POINTS=2300000                        # > 2,097,153 required; margin for growth
BYTES=$(( POINTS * 64 ))              # ~140 MiB
DAT="flutter/assets/srs_g1.dat"       # temporary raw download
SRS="flutter/assets/srs_g1.srs"       # bundled asset
URL="https://crs.aztec.network/g1.dat"

mkdir -p flutter/assets
if [ -s "$SRS" ]; then
  echo "$SRS already present ($(wc -c < "$SRS") bytes) — skipping. Delete it to re-fetch."
  exit 0
fi
echo "1/2  downloading $(( BYTES / 1024 / 1024 )) MiB of the BN254 G1 SRS from $URL"
curl -fL --retry 3 -r "0-$(( BYTES - 1 ))" -o "$DAT" "$URL"
echo "2/2  converting $DAT -> $SRS (bincode .srs)"
cargo run --release --quiet --bin gen_srs -- "$DAT" "$SRS"
rm -f "$DAT"
echo "done: $SRS ($(wc -c < "$SRS") bytes)."
echo
echo "Next: uncomment '- assets/srs_g1.srs' in flutter/pubspec.yaml, then run flutter build."
