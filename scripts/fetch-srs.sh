#!/usr/bin/env bash
# Fetch the BN254 G1 SRS prefix this circuit needs into flutter/assets/, so `flutter build`
# bundles it and the Noir path can prove OFFLINE (no ~128 MB SRS download on every launch).
#
# The file is gitignored (128 MB > GitHub's 100 MB per-file limit — same reason the Groth16
# zkey lives on GCS, not in the repo). Run this once before building the app for offline use,
# then uncomment the `- assets/srs_g1.dat` line in flutter/pubspec.yaml.
#
# Size: noir-rs needs circuit_size * ULTRA_HONK_SRS_MULTIPLIER(8) + 1 points, 64 bytes each.
# The current circuit (262,144) needs ~128 MiB; we grab a margin. Bump POINTS if you enlarge
# the circuit (a too-small file makes noir-rs panic in from_dat_file). The loader reads only
# what it needs and ignores the rest, so over-fetching is harmless.
set -euo pipefail
cd "$(dirname "$0")/.."

POINTS=2300000                        # > 2,097,153 required; margin for growth
BYTES=$(( POINTS * 64 ))              # ~140 MiB
DEST="flutter/assets/srs_g1.dat"
URL="https://crs.aztec.network/g1.dat"

mkdir -p flutter/assets
echo "Fetching $(( BYTES / 1024 / 1024 )) MiB of the BN254 G1 SRS"
echo "  from $URL  ->  $DEST"
curl -fL --retry 3 -r "0-$(( BYTES - 1 ))" -o "$DEST" "$URL"
echo "done: $(wc -c < "$DEST") bytes."
echo
echo "Next: uncomment '- assets/srs_g1.dat' in flutter/pubspec.yaml, then run flutter build."
