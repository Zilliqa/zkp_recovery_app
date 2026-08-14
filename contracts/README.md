# On-chain verifier regression tests

Foundry tests that assert the **single ABI-encoded calldata blob the Flutter app produces**
(`ProofResult.abiEncodedHex`) is accepted by the deployed verifier — for both variants.

- `test/Verifiers.t.sol`
  - `test_groth16_app_calldata_verifies` — deploys `Groth16Verifier` (from
    `../groth16-prover-min/verifier.sol`) and submits `fixtures/groth16_calldata.hex` as raw
    calldata; requires `verify() == true`. That blob is `encodeCallData`'s output: selector +
    `verifyProof(uint[2],uint[2][2],uint[2],uint[3])` args (fixed-size, flat words).
  - `test_noir_app_calldata_verifies` — deploys `HonkVerifier` (from
    `../noir-prover-min/verifier.sol`) and submits `fixtures/noir_calldata.hex`; requires
    `verify() == true`. That blob is `encodeNoirCallData`'s output: selector +
    `verify(bytes,bytes32[])` args (dynamic — offsets + lengths).

The verifiers are imported straight from the prover-min folders via remappings (no copies).

## Run
```bash
cd contracts && forge test -vv
```

## Fixtures
`fixtures/*.hex` are real proofs (Groth16 arkworks / Noir UltraHonk-keccak) for the all-zero-ish
test vector, encoded exactly as the app encodes them. The matching Dart-side check that
`encodeNoirCallData` reproduces `noir_calldata.hex` byte-for-byte lives at
`../flutter/test/noir_calldata_test.dart` (`flutter test`).

To regenerate after a circuit/verifier change, produce a fresh proof and re-encode:
- Noir: `noir-prover-min` → `target/proof` + `target/public_inputs`; blob =
  `\x00\x00\x00\x03` ++ `public_inputs` ++ `proof`; then
  `cast calldata "verify(bytes,bytes32[])" 0x<proof> "[<pub0>,<pub1>,<pub2>]"`.
- Groth16: generate an arkworks proof, then
  `cast calldata "verifyProof(uint256[2],uint256[2][2],uint256[2],uint256[3])" "[ax,ay]" "[[bx1,bx0],[by1,by0]]" "[cx,cy]" "[in0,in1,in2]"`
  (note the swapped G2 coordinates).
