#!/usr/bin/env bash
# Reproducibly compile the MINIMAL circuit from source and verify it matches the shipped artifacts.
# Source: circuit.circom + bip32lib.circom (in this folder); the rest are pinned third-party
# includes fetched below. Requires: git, node/npm, and circom 2.2.3 on PATH
#   (build it from https://github.com/iden3/circom at tag v2.2.3 -> target/release/circom).
#
# Verified reproducible — outputs are BYTE-IDENTICAL to the shipped artifacts:
#   circuit.wasm : 7349240 bytes, md5 c4281b70ecd68147bef702fe71cde160
#   circuit.r1cs : 132857964 bytes   (~679k constraints: 524094 non-linear + 155324 linear)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-/tmp/zil-min-circuit-build}"
command -v circom >/dev/null || { echo "circom not on PATH — build circom 2.2.3 from iden3/circom@v2.2.3"; exit 1; }
[ "$(circom --version | grep -o '2\.2\.3')" = "2.2.3" ] || echo "WARNING: circom is not 2.2.3 — byte-identical output not guaranteed"

mkdir -p "$WORK"; cd "$WORK"
# --- pinned third-party includes (in audit scope) ---
[ -d circom-ecdsa ] || git clone -q https://github.com/0xPARC/circom-ecdsa.git
( cd circom-ecdsa && git checkout -q d87eb7068cb35c951187093abe966275c1839ead )
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
echo "       expected 7349240 bytes  md5 c4281b70ecd68147bef702fe71cde160"
echo "r1cs : $(stat -c%s "$WORK/circuit.r1cs") bytes   (expected 132857964)"
