import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:bech32/bech32.dart';
import 'package:bip32_keys/bip32_keys.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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

    log("ZIL: ${bytesToHex(zilAddress)}");
    log("EVM: ${bytesToHex(evmAddress)}");

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
    final inputs = {
      'seed': expand512(seed),
      'accountIndex': accountIndex.toString(),
      'expectedAddr': BigInt.parse(bytesToHex(zilAddress)).toString(),
      'newAddr': BigInt.parse(bytesToHex(evmAddress)).toString(),
      'domain': '33333', // TODO: Hard-code domain separator
    };

    // Compute the Circom proof
    CircomProofResult? result;
    final zkeyPath = '${(await _getCacheDir()).path}/ledger_final.zkey';
    try {
      result = await generateCircomProof(
        zkeyPath: zkeyPath,
        circuitInputs: jsonEncode(inputs),
        proofLib: ProofLib.arkworks,
      ); // DO NOT change the proofLib if you don't build for rapidsnark
    } on Exception catch (e) {
      log("ERROR: ${e.toString()}");
      log("INPUT: ${inputs.toString()}");
      rethrow;
    }

    // Sample proof.json
    // {"pi_a":["5776502265472665278545497413361249074636339359053766956191787172828408931600","19263940612329229010478124878252338828767017689135906138173595313335781345156","1"],"pi_b":[["8748157903016795952497456733415715907038043025002955466271923316102605554524","886241302875595676424104021652447587813136273860411421594659396476663865418"],["2366384505827240099277823637769490919639979409247333838210784765674118166817","18897666235681030630830142251418440454721963148432445230139588728456976519923"],["1","0"]],"pi_c":["5919590180065651006466053140454899663463559555450770658584387679159065723805","1020193184100732785795472624075572575276220684902432661948682301798054533103","1"],"protocol":"groth16","curve":"bn128"}
    final proof = {
      'pi_a': [result.proof.a.x, result.proof.a.y, result.proof.a.z],
      'pi_b': [result.proof.b.x, result.proof.b.y, result.proof.b.z],
      'pi_c': [result.proof.c.x, result.proof.c.y, result.proof.c.z],
      'protocol': result.proof.protocol,
      'curve': result.proof.curve,
    };
    // Sample public.json
    // ["594091409465972267269143250280589291679441903583","394365017111200287840249441287420187482473354350","33333"]
    final public = [
      inputs['expectedAddr'],
      inputs['newAddr'],
      inputs['domain'],
    ];

    // Encode the calldata
    log("PROOF: $proof");
    log("PUBLIC: $public");

    final buffer = encodeVerifyProofCalldata(
      proof: result.proof,
      pubSignals: [
        inputs['expectedAddr'].toString(),
        inputs['newAddr'].toString(),
        inputs['domain'].toString(),
      ],
    );
    final calldata = bytesToHex(buffer);

    log("CALLDATA: $calldata");
    return ProofResult(
      proof: 'proof.proof',
      publicOutputs: 'proof.publicSignals',
      abiEncodedHex: calldata,
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

      log("ADDR: ${bytesToHex(derivedAddress)}");

      if (listEquals(knownKey, derivedAddress)) {
        log("${bytesToHex(knownKey)} found at $n");
        return n;
      }
      await Future.delayed(Duration.zero); // yield to prevent UI freeze
    }

    // Not found in the first `maxIndex` derived keys
    throw Exception('Key not found within $maxIndex derived keys');
  }


  Uint8List hexToBytes(String hex) {
    String cleaned = hex.startsWith('0x') || hex.startsWith('0X')
        ? hex.substring(2)
        : hex;

    // Pad with a leading zero if odd length (e.g. "0x1" -> "01")
    if (cleaned.length % 2 != 0) {
      cleaned = '0$cleaned';
    }

    final result = Uint8List(cleaned.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      final byteStr = cleaned.substring(i * 2, i * 2 + 2);
      result[i] = int.parse(byteStr, radix: 16);
    }
    return result;
  }

  String bytesToHex(Uint8List buffer) {
    return '0x${buffer.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
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

  BigInt _parseFieldElement(String s) {
    // mopro/arkworks typically output decimal strings; adjust if hex.
    return BigInt.parse(s);
  }

  Uint8List _bigIntToUint256(BigInt value) {
    final bytes = Uint8List(32);
    var v = value;
    for (int i = 31; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return bytes;
  }

  /// Converts a G1 point (affine, z assumed == "1") to [x, y] BigInts.
  List<BigInt> g1ToCalldata(G1 p) {
    assert(p.z == '1', 'Expected affine G1 point (z=1), got z=${p.z}');
    return [_parseFieldElement(p.x), _parseFieldElement(p.y)];
  }

  /// Converts a G2 point (affine, z assumed == ["1","0"]) to the
  /// [[x1,x0],[y1,y0]] order Solidity verifiers expect (snarkjs-style swap).
  List<List<BigInt>> g2ToCalldata(G2 p) {
    assert(
      p.x.length == 2 && p.y.length == 2,
      'Expected Fp2 coordinates (2 elements) for G2 point',
    );
    final x0 = _parseFieldElement(p.x[0]);
    final x1 = _parseFieldElement(p.x[1]);
    final y0 = _parseFieldElement(p.y[0]);
    final y1 = _parseFieldElement(p.y[1]);

    // snarkjs/Solidity verifier convention swaps the Fp2 component order.
    return [
      [x1, x0],
      [y1, y0],
    ];
  }

  Uint8List encodeVerifyProofCalldata({
    required CircomProof proof,
    required List<String> pubSignals, // proof.inputs, as decimal strings
  }) {
    assert(pubSignals.length == 3, 'Expected exactly 3 public signals');

    final pA = g1ToCalldata(proof.a);
    final pB = g2ToCalldata(proof.b);
    final pC = g1ToCalldata(proof.c);
    final pubSignalsBig = pubSignals.map(_parseFieldElement).toList();

    // const signature =
    //     'verifyProof(uint256[2],uint256[2][2],uint256[2],uint256[3])';
    final selector = Uint8List.fromList([0x11, 0x47, 0x9f, 0xea]); // hardcoded

    final words = <BigInt>[
      pA[0],
      pA[1],
      // NB: pB ordering needs to be flipped
      pB[0][1],
      pB[0][0],
      pB[1][1],
      pB[1][0],
      pC[0],
      pC[1],
      pubSignalsBig[0],
      pubSignalsBig[1],
      pubSignalsBig[2],
    ];

    final builder = BytesBuilder();
    builder.add(selector);
    for (final w in words) {
      builder.add(_bigIntToUint256(w));
    }

    return builder.toBytes();
  }
}
