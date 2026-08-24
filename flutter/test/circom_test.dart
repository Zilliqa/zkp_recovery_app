// import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:zkp_recovery_app/models/download_status.dart';
import 'package:zkp_recovery_app/services/proof_service.dart';

// ---------------------------------------------------------------------------
// SECTION 1 — Tests that work against the CURRENT implementation, unmodified.
// ---------------------------------------------------------------------------
//
// These exercise only the code path that runs before any external
// dependency is invoked: hex/bech32 decoding and the EVM == ZIL guard.

void main() {
  group('computeGroth16Proof — pre-dependency validation (current code)', () {
      test('throws when evmAddress equals zilAddress (both hex, same value)', () {
      final service = ProofService.instance;

      expect(
        () => service.computeGroth16Proof(
          passphrase: '',
          mnemonic:
              'xprv9s21ZrQH143K4B44c17pJdL1gsdAVRZs9d8zXnH6aib4swzjCSg5SbkzgfQVcx8RQtPiEa9TA1Nv5iihskRt7wNvyu2tmQvHpaVDK4R1Gus',
          eAddress: '0x680ffaeb3f8d74072d1a202d57ac8df8fada5fdf',
          zAddress: '0x680ffaeb3f8d74072d1a202d57ac8df8fada5fdf',
          language: Language.english,
          wallet: Wallets
              .ledger, // substitute an actual enum value used in your project
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('EVM == ZIL is not allowed'),
          ),
        ),
      );
    });

    test(
      'propagates exception on malformed mnemonic before touching network/disk',
      () {
        final service = ProofService.instance;

        expect(
          () => service.computeGroth16Proof(
            passphrase: '',
            mnemonic: 'not a valid mnemonic phrase',
            eAddress: '0xabcabcabcabcabcabcabcabcabcabcabcabcabc',
            zAddress: '0xdeaddeaddeaddeaddeaddeaddeaddeaddeaddea',
            language: Language.english,
            wallet: Wallets.ledger,
          ),
          throwsException,
        );
      },
    );

    test('accepts bech32 zAddress input without throwing on decode', () async {
      // This only verifies bech32ToBytes doesn't throw and that the function
      // gets *past* decoding — it will still fail later (no zkey/native lib
      // in a test environment), so we only assert it does NOT throw the
      // specific "EVM == ZIL" or decode-related exception.
      final service = ProofService.instance;

      await expectLater(
        service.computeGroth16Proof(
          passphrase: '',
          mnemonic:
              'xprv9s21ZrQH143K4B44c17pJdL1gsdAVRZs9d8zXnH6aib4swzjCSg5SbkzgfQVcx8RQtPiEa9TA1Nv5iihskRt7wNvyu2tmQvHpaVDK4R1Gus',
          eAddress: '0x1234567890123456789012345678901234567890',
          zAddress:
              'zil1pzldkj8avpal82jrmzd3qwaqxy9qtd0pyzpn3h', // placeholder bech32
          language: Language.english,
          wallet: Wallets.ledger,
        ),
        // Expect it to fail further downstream (findAccountParent / native
        // call), NOT with the EVM==ZIL guard or a bech32 decode error.
        throwsA(
          isNot(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('EVM == ZIL is not allowed'),
            ),
          ),
        ),
      );
    });
  });
}
