import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:bech32/bech32.dart';
import 'package:bip32_keys/bip32_keys.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web3dart/web3dart.dart';

import 'package:mopro_flutter_bindings/src/rust/third_party/ledger_mopro_app.dart';

/// Result of a Groth16 proof computation: the proof itself and the
/// public outputs it attests to, plus the combined Solidity
/// `abi.encode(bytes,bytes)` payload ready to paste into a wallet.
class ProofResult {
  final String proof;
  final String publicOutputs;
  final String abiEncodedHex;

  const ProofResult({
    required this.proof,
    required this.publicOutputs,
    required this.abiEncodedHex,
  });
}

class ProofService {
  ProofService._();
  static final ProofService instance = ProofService._();

  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/proving_artifacts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// STUB: replace with the real Groth16 witness generation + proving
  /// pipeline (using ledger.zkey / ledger.wsd) once it's ready.
  ///
  /// [mnemonic] is the 12-word seed phrase, [evmAddress] is the freshly
  /// generated EVM-only account that should receive funds. Both are
  /// expected to already be validated by the caller (see InputDialog).
  Future<ProofResult> computeGroth16Proof({
    required String passphrase,
    required String mnemonic,
    required String eAddress,
    required String zAddress,
    required Language language,
  }) async {
    // Extract addresses
    final evmAddress = hexToBytes(eAddress);
    final zilAddress = (zAddress.startsWith('0x')
        ? hexToBytes(zAddress)
        : bech32ToBytes(zAddress));
    if (listEquals(evmAddress, zilAddress)) {
      throw Exception("EVM == ZIL is not allowed");
    }

    log("ZIL: ${bytesToHex(zilAddress, include0x: true)}");
    log("EVM: ${bytesToHex(evmAddress, include0x: true)}");

    // Compute BIP39 mnemonic seed; throws exception if invalid.
    final bip39 = Mnemonic.fromSentence(
      mnemonic,
      language,
      passphrase: passphrase,
    );
    final seed = Uint8List.fromList(bip39.seed);

    // Find old account index; throws exception if not found
    final accountIndex = await findAccountIndex(
      seed: seed,
      knownKey: zilAddress,
    );

    // Encode the Circom inputs
    /*
{
  seed: [
    1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 1,
    0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0,
    1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1,
    0, 0, 1, 0, 1, 1, 1, 0, 1, 1, 0, 0,
    1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0,
    0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1,
    0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0,
    1, 1, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1,
    1, 0, 0, 0,
    ... 412 more items
  ],
  accountIndex: '5',
  expectedAddr: '594091409465972267269143250280589291679441903583',
  newAddr: '394365017111200287840249441287420187482473354350',
  domain: '33333'
}
    */
    final inputs = jsonEncode({
      'seed': expand512(seed),
      'accountIndex': accountIndex.toString(),
      'expectedAddr': BigInt.parse(
        bytesToHex(zilAddress, include0x: true),
      ).toString(),
      'newAddr': BigInt.parse(
        bytesToHex(evmAddress, include0x: true),
      ).toString(),
      'domain': '33333', // TODO: Hard-code domain separator
    });

    // Compute the Circom proof
    CircomProofResult? proofResult;
    final zkeyPath = '${(await _getCacheDir()).path}/ledger_final.zkey';
    try {
      proofResult = await generateCircomProof(
        zkeyPath: zkeyPath,
        circuitInputs: inputs,
        proofLib: ProofLib.arkworks,
      ); // DO NOT change the proofLib if you don't build for rapidsnark
      log("PROOF: ${proofResult.proof}");
    } on Exception catch (e) {
      log("ERROR: ${e.toString()}");
      log("INPUT: ${inputs.toString()}");
      rethrow;
    }

    // Encode the calldata
    final buffer = _abiEncodeCallData(
      proofResult.proof.toString(),
      proofResult.inputs.toString(),
    );
    log("PROOF: ${bytesToHex(buffer, include0x: true)}");
    return ProofResult(
      proof: 'proof.proof',
      publicOutputs: 'proof.publicSignals',
      abiEncodedHex: bytesToHex(buffer, include0x: true),
    );
  }

  Uint8List expand512(Uint8List bytes) {
    // bytes.length should be 64 for a 512-bit output (64 * 8 = 512)
    final List<int> bits = List<int>.filled(bytes.length * 8, 0);
    int idx = 0;
    for (final x in bytes) {
      for (int i = 7; i >= 0; i--) {
        bits[idx++] = (x >> i) & 1;
      }
    }
    return Uint8List.fromList(bits);
  }

  /// Searches derivation indices m/44'/313'/n'/0'/0' for n in [0, maxIndex)
  /// and returns the matching index, or throws if none of the derived
  /// keys match [knownKey]. This path is unique to Ledger-Zilliqa.
  Future<int> findAccountIndex({
    required Uint8List seed,
    required Uint8List knownKey,
    int maxIndex = 100,
  }) async {
    // Master key, derived once - each path derivation walks down from here.
    final masterKey = Bip32Keys.fromSeed(seed);

    // Derive m/44'/313'/n'/0'/0' for n = 0..maxIndex and compare
    for (int n = 0; n < maxIndex; n++) {
      final path = "m/44'/313'/$n'/0'/0'"; // TODO: Verify vs Ledger app
      final derivedKey = masterKey.derivePath(path);
      final derivedAddress = Uint8List.fromList(
        sha256.convert(derivedKey.public).bytes,
      ).sublist(12);

      log("PUB: ${bytesToHex(derivedAddress, include0x: true)}");

      if (listEquals(knownKey, derivedAddress)) {
        log("${bytesToHex(knownKey, include0x: true)} found at $n");
        return n;
      }
      await Future.delayed(Duration.zero); // yield to prevent UI freeze
    }

    // Not found in the first `maxIndex` derived keys
    throw Exception('Key not found within $maxIndex derived keys');
  }

  /// Decode zil1xxx address
  Uint8List bech32ToBytes(String address) {
    // Validate Bech32 checksum.
    Bech32 b = Bech32Decoder().convert(address);

    // Map 5b8b
    int buffer = 0;
    int bits = 0;
    List<int> bytes = [];
    for (int value in b.data) {
      buffer = (buffer << 5) | value;
      bits += 5;
      while (bits >= 8) {
        bits -= 8;
        bytes.add((buffer >> bits) & 0xFF);
      }
    }
    return Uint8List.fromList(bytes);
  }

  /// Calldata encoding
  Uint8List _abiEncodeCallData(String a, String b) {
    // 1. Define a dummy function with signature matching: bytes, bytes
    final dummyFunction = ContractFunction(
      'submitProof', //
      [
        FunctionParameter('a', parseAbiType('string')),
        FunctionParameter('b', parseAbiType('string')),
      ],
    );

    return dummyFunction.encodeCall([a, b]);
  }
}
