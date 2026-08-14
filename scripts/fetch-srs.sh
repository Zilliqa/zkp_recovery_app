#!/usr/bin/env bash
# Fetch the bundled offline SRS (flutter/assets/srs_g1.srs) so `flutter build` bakes it in and the
# Noir path proves OFFLINE (no per-launch download). Idempotent; run once before `flutter build`.
#
# Source order:
#   1. PRIMARY  — GCS: the finished bincode .srs (fast, no build tools needed).
#   2. FALLBACK — the authentic Aztec CRS: raw g1.dat prefix -> `gen_srs` -> .srs (needs cargo).
# Both paths yield the identical file, checked against SRS_SHA256. The .srs is git-ignored
# (~140 MB > GitHub's 100 MB limit). If you enlarge the circuit, bump POINTS, regenerate via
# gen_srs, re-upload to GCS, and update SRS_SHA256.
set -euo pipefail
cd "$(dirname "$0")/.."

SRS="flutter/assets/srs_g1.srs"
SRS_SHA256="afc399b60d38bfadf06cea3ce824f0aff475c3eec3a44163b81a560b0bc38a07"
GCS_URL="https://storage.googleapis.com/bkt-p-zkproof-files-001/noir/srs_g1.srs"
AZTEC_URL="https://crs.aztec.network/g1.dat"
POINTS=2300000                         # aztec fallback: g1.dat prefix (> 2,097,153 required)

mkdir -p flutter/assets
verify() { echo "${SRS_SHA256}  ${SRS}" | sha256sum -c - >/dev/null; }

if [ -s "$SRS" ]; then
  echo "$SRS already present ($(wc -c < "$SRS") bytes) — skipping. Delete it to re-fetch."
  exit 0
fi

# 1) PRIMARY: GCS
echo "[primary] GCS: $GCS_URL"
if curl -fL --retry 3 -o "$SRS" "$GCS_URL" && verify; then
  echo "done (GCS): $(wc -c < "$SRS") bytes, checksum OK."
  exit 0
fi
echo "[primary] GCS failed or checksum mismatch — falling back to the authentic Aztec CRS."
rm -f "$SRS"

# 2) FALLBACK: authentic Aztec CRS (raw .dat -> gen_srs -> .srs)
export PATH="$HOME/.cargo/bin:$PATH"
command -v cargo >/dev/null || { echo "ERROR: cargo needed for the Aztec fallback (converts .dat -> .srs)"; exit 1; }
DAT="flutter/assets/srs_g1.dat"
BYTES=$(( POINTS * 64 ))
echo "[fallback] downloading $(( BYTES / 1024 / 1024 )) MiB from $AZTEC_URL"
curl -fL --retry 3 -r "0-$(( BYTES - 1 ))" -o "$DAT" "$AZTEC_URL"
echo "[fallback] converting $DAT -> $SRS via gen_srs"
cargo run --release --quiet --bin gen_srs -- "$DAT" "$SRS"
rm -f "$DAT"
verify || { echo "ERROR: checksum mismatch after Aztec fallback"; rm -f "$SRS"; exit 1; }
echo "done (Aztec fallback): $(wc -c < "$SRS") bytes, checksum OK."
