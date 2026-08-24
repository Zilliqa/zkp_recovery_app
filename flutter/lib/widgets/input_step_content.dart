import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:eip55/eip55.dart';
import 'package:flutter/material.dart';
import 'package:zkp_recovery_app/models/download_status.dart';

class InputStepContent extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController passwordController;
  final TextEditingController mnemonicController;
  final TextEditingController evmAddressController;
  final TextEditingController zilAddressController;
  final bool obscureMnemonic;
  final bool obscurePassword;
  final bool isComputingProof;
  final VoidCallback onToggleObscure;
  final VoidCallback onTogglePassword;
  final String? computeError;
  final void Function(Language?) onSelectedLanguage;
  final void Function(Wallets?) onSelectedWallet;

  const InputStepContent({
    super.key,
    required this.formKey,
    required this.mnemonicController,
    required this.evmAddressController,
    required this.zilAddressController,
    required this.obscureMnemonic,
    required this.onToggleObscure,
    required this.onSelectedLanguage,
    required this.passwordController,
    required this.onTogglePassword,
    required this.obscurePassword,
    required this.isComputingProof,
    required this.onSelectedWallet,
    this.computeError,
  });

  String? _validateMnemonic(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Mnemonic-seed is required';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length != 12 &&
        words.length != 15 &&
        words.length != 18 &&
        words.length != 21 &&
        words.length != 24) {
      return 'Expected 12/15/18/21/24 words, got ${words.length}';
    }
    if (!words.every((w) => w == w.toLowerCase())) {
      return 'Words should be lowercase letters only';
    }
    return null;
  }

  String? _validateAddressEvm(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'EVM address is required';
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(trimmed)) {
      return 'Expected a 0x-prefixed address';
    }
    final eip55 = toEIP55Address(trimmed);
    if (eip55 != trimmed) {
      return 'Invalid EIP-55 address';
    }
    return null;
  }

  String? _validateAddressZil(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'ZIL address is required';
    if (!RegExp(
      r'(^0x[0-9a-fA-F]{40}$|^zil1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{38}$)',
    ).hasMatch(trimmed)) {
      return 'Expected a zil1-prefixed address';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: formKey,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enable Flight mode and disable WiFi for this step.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            enabled: !isComputingProof,
            controller: zilAddressController,
            decoration: const InputDecoration(
              labelText: 'Old Schnorr account address',
              hintText: 'zil1… or 0x…',
              border: OutlineInputBorder(),
            ),
            validator: _validateAddressZil,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 16),
          TextFormField(
            enabled: !isComputingProof,
            controller: evmAddressController,
            decoration: const InputDecoration(
              labelText: 'New EVM-only account address',
              hintText: '0x…',
              border: OutlineInputBorder(),
            ),
            validator: _validateAddressEvm,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 16),
          Text('Original seed wallet', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          DropdownMenu<Wallets>(
            enabled: !isComputingProof,
            initialSelection: Wallets.ledger,
            onSelected: onSelectedWallet,
            dropdownMenuEntries: Wallets.values.map((Wallets wallet) {
              return DropdownMenuEntry<Wallets>(
                value: wallet,
                label: wallet.name
                    .toUpperCase(), // Prints readable text (ADMIN, EDITOR...)
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            'Your mnemonic-seed/private-key is only used locally on this device to compute the proof and is never transmitted.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextFormField(
            enabled: !isComputingProof,
            controller: mnemonicController,
            obscureText: (obscureMnemonic || isComputingProof),
            maxLines: 1,
            decoration: InputDecoration(
              labelText: 'Mnemonic-seed or Private-key',
              hint: const Text('12/15/18/21/24-word mnemonic'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  obscureMnemonic ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            validator: _validateMnemonic,
            autocorrect: false,
            enableSuggestions: false,
            enableInteractiveSelection: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: null,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 8),
          DropdownMenu<Language>(
            enabled: !isComputingProof,
            initialSelection: Language.english,
            onSelected: onSelectedLanguage,
            dropdownMenuEntries: Language.values.map((Language lang) {
              return DropdownMenuEntry<Language>(
                value: lang,
                label: lang.name
                    .toUpperCase(), // Prints readable text (ADMIN, EDITOR...)
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            enabled: !isComputingProof,
            controller: passwordController,
            obscureText: obscurePassword || isComputingProof,
            maxLines: 1,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              hint: const Text('(blank if none)'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: onTogglePassword,
              ),
            ),
            // validator: _validateMnemonic,
            autocorrect: false,
            enableSuggestions: false,
            enableInteractiveSelection: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: null,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 16),
          Text(
            'This computation can take several minutes. Please be patient.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
          if (computeError != null) ...[
            const SizedBox(height: 12),
            Text(
              computeError!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
