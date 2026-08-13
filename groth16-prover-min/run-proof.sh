#!/usr/bin/env bash
# Minimal-circuit GROTH16 proof runner. Off-circuit: derive the m/44'/313'/n'/0' parent node.
# usage: ./run-proof.sh "<mnemonic>" <oldAddr 0x..|zil1..> <newAddr> <domain dec|0x..>
set -e
[ -d node_modules ] || npm install @scure/bip39 @scure/bip32 snarkjs
node prepare.js "$1" "$2" "$3" "$4"
node circuit_js/generate_witness.js circuit_js/circuit.wasm circuit_in.json circuit.wtns
SNARKJS="node --max-old-space-size=8192 node_modules/snarkjs/build/cli.cjs"
echo "proving (Groth16, minimal circuit ~427k constraints)..."
$SNARKJS groth16 prove circuit_final.zkey circuit.wtns proof.json public.json >/dev/null
if $SNARKJS groth16 verify vk.json public.json proof.json 2>&1 | grep -q OK; then
  echo "RESULT: PROOF VERIFIED — seed ownership of OLD addr, bound to NEW addr + domain"
else echo "RESULT: VERIFY FAILED"; fi
rm -f circuit_in.json circuit.wtns
echo "saved proof.json/public.json; sensitive inputs wiped"
node print_submit.js
