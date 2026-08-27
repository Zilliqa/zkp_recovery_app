#!/usr/bin/env bash
# Terminal ceremony contribution tool.
#   1. Download the ceremony's current key into this folder as  current.zkey  (manual).
#   2. Run this script — it mixes in fresh randomness and writes  contribution.zkey.
#   3. Upload  contribution.zkey  to the coordinator and report the printed hash (manual).
# usage: ./contribute.sh [inputKey=current.zkey] [outputKey=contribution.zkey]
set -e
cd "$(dirname "$0")"
[ -d node_modules ] || { echo "installing snarkjs (first run)..."; npm install --no-audit --no-fund snarkjs; }
# large Node heap: the ~358 MB minimal-circuit key needs several GB of RAM to transform
node --max-old-space-size=16384 contribute.js "$@"
