import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkp_recovery_app/services/proof_service.dart';

Uint8List _hex(String s) {
  s = s.trim();
  if (s.startsWith('0x')) s = s.substring(2);
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Regression: encodeNoirCallData must turn the raw noir-rs proof blob
  // ([numPubs][pubs][proof]) into the exact single ABI-encoded
  // verify(bytes,bytes32[]) calldata that the on-chain HonkVerifier accepts
  // (the forge test in ../contracts checks that same fixture verifies on-chain).
  test('encodeNoirCallData builds the on-chain verify(bytes,bytes32[]) calldata', () {
    final blob = _hex(File('test/fixtures/noir_proof_blob.hex').readAsStringSync());
    final expected =
        File('test/fixtures/noir_calldata.hex').readAsStringSync().trim();
    final calldata = ProofService.instance.encodeNoirCallData(blob);
    expect('0x${_toHex(calldata)}', equals(expected));
  });
}
