#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
S="node --max-old-space-size=16384 node_modules/snarkjs/build/cli.cjs"
echo "=== PLONK SETUP (minimal circuit, pot 2^21) ==="
/usr/bin/time -v $S plonk setup circuit.r1cs pot.ptau circuit_plonk.zkey 2> setup.time.txt >/dev/null
grep -E 'Elapsed \(wall|Maximum resident' setup.time.txt
echo "plonk key size: $(du -h circuit_plonk.zkey | cut -f1)"
$S zkey export verificationkey circuit_plonk.zkey vk.json >/dev/null 2>&1
$S zkey export solidityverifier circuit_plonk.zkey verifier.sol >/dev/null 2>&1
echo "=== witness ==="; node circuit_js/generate_witness.js circuit_js/circuit.wasm input.json witness.wtns
echo "=== PLONK PROVE (time + RAM) ==="
/usr/bin/time -v $S plonk prove circuit_plonk.zkey witness.wtns proof.json public.json 2> prove.time.txt >/dev/null
grep -E 'Elapsed \(wall|Maximum resident' prove.time.txt
echo "=== PLONK VERIFY ==="; $S plonk verify vk.json public.json proof.json 2>&1 | grep -iE 'OK|INVALID'
echo "DONE-PLONK-MIN"
