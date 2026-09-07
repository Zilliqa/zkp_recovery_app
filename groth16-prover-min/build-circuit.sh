#!/usr/bin/env bash
# Reproducibly compile the MINIMAL circuit from source and verify it matches the shipped artifacts.
# Source: circuit.circom + bip32lib.circom (in this folder); the rest are pinned third-party
# includes fetched below. Requires: git, node/npm, and circom 2.2.3 on PATH
#   (build it from https://github.com/iden3/circom at tag v2.2.3 -> target/release/circom).
#
# Verified reproducible — outputs are BYTE-IDENTICAL to the shipped artifacts:
#   circuit.wasm : 7349308 bytes, md5 bae8fe8d280d6776c0cc68903425c3ad
#   circuit.r1cs : 132858048 bytes   (~679k constraints: 524095 non-linear + 155324 linear)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-/tmp/zil-min-circuit-build}"
command -v circom >/dev/null || { echo "circom not on PATH — build circom 2.2.3 from iden3/circom@v2.2.3"; exit 1; }
[ "$(circom --version | grep -o '2\.2\.3')" = "2.2.3" ] || echo "WARNING: circom is not 2.2.3 — byte-identical output not guaranteed"

mkdir -p "$WORK"; cd "$WORK"
# --- pinned third-party includes (in audit scope) ---
[ -d circom-ecdsa ] || git clone -q https://github.com/0xPARC/circom-ecdsa.git
( cd circom-ecdsa && git checkout -q -f d87eb7068cb35c951187093abe966275c1839ead )
# F-2026-19094(a): patch circom-ecdsa's get_dummy_point placeholder from 255*G to the intended 2^255*G
# (the library's comment promised 2^255*G but the literal encoded 255*G), then independently verify it.
( cd circom-ecdsa && git apply "$HERE/patches/circom-ecdsa-dummy-point.patch" )
node "$HERE/check-dummy-point.js" circom-ecdsa/circuits/secp256k1_func.circom
( cd circom-ecdsa && npm install -q --no-audit --no-fund circomlib@2.0.2 >/dev/null )
[ -d sha512 ] || git clone -q https://github.com/Electron-Labs/sha512.git
( cd sha512 && git checkout -q be9f01d870c40c3fe4e0ff27c93232d205bc46f7 )
# --- our source ---
cp "$HERE/circuit.circom" "$HERE/bip32lib.circom" circom-ecdsa/circuits/

# --- compile (same flags used for the shipped artifacts) ---
cd circom-ecdsa
circom circuits/circuit.circom --r1cs --wasm --O1 -o "$WORK" \
  -l node_modules/circomlib/circuits -l ../sha512/circuits/sha512

# --- verify against the shipped artifacts ---
echo; echo "=== reproducibility check ==="
echo "wasm : $(stat -c%s "$WORK/circuit_js/circuit.wasm") bytes  md5 $(md5sum "$WORK/circuit_js/circuit.wasm" | cut -d' ' -f1)"
echo "       expected 7349308 bytes  md5 bae8fe8d280d6776c0cc68903425c3ad"
echo "r1cs : $(stat -c%s "$WORK/circuit.r1cs") bytes   (expected 132858048)"
