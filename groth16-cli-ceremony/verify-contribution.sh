#!/usr/bin/env bash
# OPERATOR-ONLY: verify an uploaded contribution BEFORE promoting it to the new current.zkey.
# Confirms the key is a valid Groth16 phase-2 key for this circuit and lists its contribution
# chain (each contributor's hash, in order).
# usage:  ./verify-contribution.sh <contribution.zkey> <circuit.r1cs> <pot21.ptau>
set -e
cd "$(dirname "$0")"
ZKEY="$1"; R1CS="$2"; PTAU="$3"
[ -n "$ZKEY" ] && [ -n "$R1CS" ] && [ -n "$PTAU" ] || {
  echo "usage: ./verify-contribution.sh <contribution.zkey> <circuit.r1cs> <pot21.ptau>"; exit 1; }
for f in "$ZKEY" "$R1CS" "$PTAU"; do [ -f "$f" ] || { echo "ERROR: file not found: $f"; exit 1; }; done
[ -d node_modules ] || npm install --no-audit --no-fund snarkjs
S="node --max-old-space-size=16384 node_modules/snarkjs/build/cli.cjs"

R1CS_SHA=$(sha256sum "$R1CS" | cut -d' ' -f1)
echo "circuit.r1cs sha256: $R1CS_SHA   (must equal the hash pinned in the published transcript)"
echo "verifying $ZKEY (this takes a few minutes)..."
OUT="$($S zkey verify "$R1CS" "$PTAU" "$ZKEY" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
echo "$OUT" | grep -iE 'contribution #|ZKey Ok|INVALID' || true
echo
if echo "$OUT" | grep -qi 'ZKey Ok!'; then
  echo "RESULT: VALID (ZKey Ok!)."
  echo "Before promoting, confirm the contribution list above equals your PUBLISHED TRANSCRIPT"
  echo "plus exactly ONE new entry (the newest contributor's hash) — this rejects forks/rollbacks."
  echo "If it checks out:   mv \"$ZKEY\" current.zkey   and publish the new current.zkey."
else
  echo "RESULT: INVALID — do NOT promote this file."; exit 1
fi
