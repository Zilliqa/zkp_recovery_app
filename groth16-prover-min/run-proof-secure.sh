#!/usr/bin/env bash
# HARDENED minimal-circuit GROTH16 runner. Mnemonic typed at a hidden prompt; seed/witness stay in memory.
# usage: ./run-proof-secure.sh <oldAddr> <newAddr> <domain>
set -e
[ -d node_modules ] || npm install @scure/bip39 @scure/bip32 bip39 snarkjs
node --max-old-space-size=8192 prove-secure.js "$1" "$2" "$3"
