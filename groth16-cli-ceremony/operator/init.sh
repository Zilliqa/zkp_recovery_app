#!/usr/bin/env bash
# OPERATOR-ONLY, run ONCE at the start: create the INITIAL (zero-contribution) key that the
# FIRST contributor downloads. It's a deterministic function of the public circuit + powers-of-tau.
# usage:  ./init.sh circuit.r1cs pot.ptau
# output: current.zkey   (publish this for the first contributor; it has 0 contributions)
set -e
cd "$(dirname "$0")"
R1CS="$1"; PTAU="$2"
[ -n "$R1CS" ] && [ -n "$PTAU" ] || { echo "usage: ./init.sh circuit.r1cs pot.ptau"; exit 1; }
for f in "$R1CS" "$PTAU"; do [ -f "$f" ] || { echo "ERROR: file not found: $f"; exit 1; }; done
[ -d node_modules ] || { echo "installing snarkjs (first run)..."; npm ci --no-audit --no-fund; }
S="node --max-old-space-size=16384 node_modules/snarkjs/build/cli.cjs"

echo "generating the initial (0-contribution) key from circuit.r1cs + powers-of-tau..."
$S groth16 setup "$R1CS" "$PTAU" current.zkey
R1CS_SHA=$(sha256sum "$R1CS" | cut -d' ' -f1)
echo
echo "Initial key written: current.zkey  (0 contributions)."
echo "circuit.r1cs sha256: $R1CS_SHA"
echo "  ^ PUBLISH this in the ceremony transcript. It pins the exact circuit every contributor and"
echo "    every independent verifier must use; 'snarkjs zkey verify circuit.r1cs <ptau> <key>' is only"
echo "    meaningful against the r1cs with this hash."
echo "Publish current.zkey for the first contributor to download. circuit.r1cs and the ptau are"
echo "public too — contributors don't need them, but the operator needs them to verify uploads."
