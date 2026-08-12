#!/usr/bin/env bash
# OPERATOR-ONLY finalization — run ONCE, after all contributions are collected.
# This is NOT a normal contribution: it applies a PUBLIC random beacon to the last accepted key,
# verifies the result, and exports the verification key + on-chain verifier contract.
#
# The beacon value must be public and fixed by an external source AFTER the last contribution —
# a drand round or a future Bitcoin block hash — so anyone can confirm it wasn't cherry-picked.
#
# usage:
#   ./finalize.sh <lastKey.zkey> <circuit.r1cs> <pot.ptau> <beaconHex64> [iterations=10]
# outputs (in this folder):
#   final.zkey     -> the production proving key (ships in the proof-runner)
#   vk.json        -> verification key
#   verifier.sol   -> on-chain verifier contract
set -e
cd "$(dirname "$0")"
IN="$1"; R1CS="$2"; PTAU="$3"; BEACON="$4"; ITERS="${5:-10}"

[ -n "$IN" ] && [ -n "$R1CS" ] && [ -n "$PTAU" ] && [ -n "$BEACON" ] || {
  echo "usage: ./finalize.sh <lastKey.zkey> <circuit.r1cs> <pot.ptau> <beaconHex64> [iterations=10]"; exit 1; }
for f in "$IN" "$R1CS" "$PTAU"; do [ -f "$f" ] || { echo "ERROR: file not found: $f"; exit 1; }; done
[[ "$BEACON" =~ ^[0-9a-fA-F]{64}$ ]] || {
  echo "ERROR: beacon must be 32-byte hex (64 chars). Use a PUBLIC source fixed after the last"
  echo "       contribution — e.g. a drand round's randomness, or a future Bitcoin block hash."; exit 1; }
{ [[ "$ITERS" =~ ^[0-9]{1,2}$ ]] && [ "$ITERS" -ge 10 ] && [ "$ITERS" -le 63 ]; } || {
  echo "ERROR: iterations must be an integer 10..63 (10 is typical)."; exit 1; }

[ -d node_modules ] || { echo "installing snarkjs (first run)..."; npm install --no-audit --no-fund snarkjs; }
S="node --max-old-space-size=16384 node_modules/snarkjs/build/cli.cjs"

echo "[1/4] applying beacon (final, non-secret contribution)..."
$S zkey beacon "$IN" final.zkey "$BEACON" "$ITERS" -n="final beacon"
echo "[2/4] verifying final key against circuit.r1cs + pot.ptau..."
$S zkey verify "$R1CS" "$PTAU" final.zkey
echo "[3/4] exporting verification key -> vk.json..."
$S zkey export verificationkey final.zkey vk.json
echo "[4/4] exporting on-chain verifier contract -> verifier.sol..."
$S zkey export solidityverifier final.zkey verifier.sol

echo
echo "================= CEREMONY FINALIZED ================="
echo "Produced: final.zkey (production proving key), vk.json, verifier.sol"
echo "Publish, so anyone can verify the whole setup:"
echo "  - final.zkey / vk.json / verifier.sol"
echo "  - the full contribution transcript (all contributor hashes)"
echo "  - the beacon value and iterations used:  $BEACON  ($ITERS)"
echo "====================================================="
