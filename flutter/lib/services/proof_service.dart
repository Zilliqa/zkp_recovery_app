import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:bech32/bech32.dart';
import 'package:bip32_keys/bip32_keys.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:hashlib/hashlib.dart';
import 'package:flutter/foundation.dart';
import 'package:zkp_recovery_app/models/download_status.dart';
import 'package:zkp_recovery_app/services/download_service.dart';
import 'package:mopro_flutter_bindings/src/rust/third_party/zkp_recovery_app.dart';

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

  Future<Directory> _getCacheDir() async {
    return DownloadService.instance.getCacheDir();
  }

  /// Computes the Groth16 Proof
  ///
  /// @param passphrase (optional) passphrase
  /// @param mnemonic   The mnemonic seed phrase.
  /// @param eAddress   The clean ECDSA address.
  /// @param zAddress   The old Schnorr address.
  /// @param language   The BIP39 language set to use.
  Future<ProofResult> computeGroth16Proof({
    required String passphrase,
    required String mnemonic,
    required String eAddress,
    required String zAddress,
    required Language language,
    required Wallets wallet,
  }) async {
    await Future.delayed(Duration.zero); // yield to prevent UI freeze
    // Extract addresses
    final evmAddress = hexToBytes(eAddress);
    final zilAddress = (zAddress.startsWith('0x')
        ? hexToBytes(zAddress)
        : bech32ToBytes(zAddress));
    if (listEquals(evmAddress, zilAddress)) {
      throw Exception("EVM == ZIL is not allowed");
    }

    // Master key, derived once - each path derivation walks down from here.
    Bip32Keys? hdKey;
    try {
      // Compute master key from seed/xprv; throws exception if invalid.
      if (mnemonic.startsWith("xprv")) {
        hdKey = Bip32Keys.fromBase58(mnemonic);
      } else {
        final bip39 = Mnemonic.fromSentence(
          mnemonic,
          language,
          passphrase: passphrase,
        );
        hdKey = Bip32Keys.fromSeed(
          Uint8List.fromList(bip39.seed),
        ); // does not store seed
      }
    } catch (_) {
      rethrow;
    }

    // Find old account index; throws exception if not found
    final parent = await findAccountParent(hdKey, zilAddress, wallet);
    if (parent == null) {
      throw Exception(
        "ZIL address does not seem to be derived from mnemonic-seed or master-key.",
      );
    }

    // Encode the Circom inputs in the Arkworks format.
    // Arkworks uses a different encoding format than Rapidsnark.
    // This object serializes into the expected encoding format for Arkworks.
    final inputs = {
      'parentPriv': expand256(parent.private!),
      'parentCC': expand256(parent.chainCode),
      'expectedAddr': [BigInt.parse(bytesToHex(zilAddress)).toString()],
      'newAddr': [BigInt.parse(bytesToHex(evmAddress)).toString()],
      'domain': [
        (kDebugMode) ? '33101' : '32769',
      ], // Hard-coded domain separator
    };

    // Compute the Circom proof
    CircomProofResult? result;
    final zkeyPath = '${(await _getCacheDir()).path}/groth_final.zkey';
    // Groth16 (~1GB RAM):
    //  - FCN_sprout    : <6m
    //  - emu64xa       : <2m
    //  - Ubuntu_24.04  : <2m
    result = await generateCircomProof(
      zkeyPath: zkeyPath,
      circuitInputs: jsonEncode(inputs),
      proofLib: ProofLib.arkworks,
    );

    // Encode the outputs
    final calldata = encodeCallData(result);
    final output = ProofResult(
      proof: "",
      publicOutputs: "",
      abiEncodedHex: bytesToHex(calldata),
    );

    log(output.abiEncodedHex);
    return output;
  }

  List<String> expand256(Uint8List bytes) {
    // bytes.length should be 32 for a 256-bit output
    assert(bytes.length == 32);
    final List<String> bits = List<String>.filled(256, "");
    int idx = 0;
    for (final x in bytes) {
      for (int i = 7; i >= 0; i--) {
        bits[idx++] = ((x >> i) & 1).toString();
      }
    }
    return bits;
  }

  /// Searches derivation indices m/44'/313'/n'/0'/0' for n in [0, 1000)
  /// and returns the matching index, or throws if none of the derived
  /// keys match [knownAddress]. This path is unique to Ledger-Zilliqa.
  Future<Bip32Keys?> findAccountParent(
    Bip32Keys masterKey,
    Uint8List knownAddress,
    Wallets wallet,
  ) async {
    for (int n = 0; n < 1000; n++) {
      final derivedAddress = _deriveAddress(masterKey, wallet, n);
      if (listEquals(knownAddress, derivedAddress)) {
        log("${bytesToHex(knownAddress)} found at $n");
        return _deriveParent(masterKey, wallet, n);
      }
      await Future.delayed(Duration.zero); // yield to prevent UI freeze
    }
    return null;
  }

  // Derive m/44'/313'/n'/0'/0' for n = 0..1000 and compare
  Uint8List _deriveAddress(Bip32Keys masterKey, Wallets wallet, int n) {
    switch (wallet) {
      case Wallets.ledger:
        final derivedKey = masterKey.derivePath("m/44'/313'/$n'/0'/0'");
        return Uint8List.fromList(
          sha256.convert(derivedKey.public).bytes,
        ).sublist(12);
      default:
        throw Exception("unsupported wallet");
    }
  }

  Bip32Keys _deriveParent(Bip32Keys masterKey, Wallets wallet, int n) {
    switch (wallet) {
      case Wallets.ledger:
        return masterKey.derivePath("m/44'/313'/$n'/0'");
      default:
        throw Exception("unsupported wallet");
    }
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

  Uint8List _bigIntToUint256(BigInt value) {
    final bytes = Uint8List(32);
    var v = value;
    for (int i = 31; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return bytes;
  }

  Uint8List encodeCallData(CircomProofResult result) {
    assert(result.inputs.length == 3, 'Expected exact inputs');

    final selector = hexToBytes(
      keccak256sum(
        'verifyProof(uint256[2],uint256[2][2],uint256[2],uint256[3])',
      ).substring(0, 8),
    ); // hardcoded

    final words = [
      result.proof.a.x,
      result.proof.a.y,
      result.proof.b.x[1],
      result.proof.b.x[0],
      result.proof.b.y[1],
      result.proof.b.y[0],
      result.proof.c.x,
      result.proof.c.y,
      result.inputs[0],
      result.inputs[1],
      result.inputs[2],
    ];

    final builder = BytesBuilder();
    builder.add(selector);
    for (final word in words) {
      builder.add(_bigIntToUint256(BigInt.parse(word)));
    }
    return builder.toBytes();
  }
}
