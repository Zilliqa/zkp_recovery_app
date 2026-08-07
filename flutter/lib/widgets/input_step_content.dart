import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:flutter/material.dart';

class InputStepContent extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController passwordController;
  final TextEditingController mnemonicController;
  final TextEditingController evmAddressController;
  final TextEditingController zilAddressController;
  final bool obscureMnemonic;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onTogglePassword;
  final String? computeError;
  final void Function(Language?) onSelectedLanguage;

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
    this.computeError,
  });

  String? _validateMnemonic(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Seed phrase is required';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length != 12 && words.length != 24) {
      return 'Expected 12/24 words, got ${words.length}';
    }
    if (!words.every((w) => RegExp(r'^[a-z]+$').hasMatch(w))) {
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
            controller: zilAddressController,
            decoration: const InputDecoration(
              labelText: 'Old Schnorr account address',
              hintText: 'zil1…',
              border: OutlineInputBorder(),
            ),
            validator: _validateAddressZil,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 16),
          TextFormField(
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
          Text(
            'Your seed phrase is only used locally on this device to compute the proof and is never transmitted.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: mnemonicController,
            obscureText: obscureMnemonic,
            maxLines: obscureMnemonic ? 1 : 3,
            decoration: InputDecoration(
              labelText: '12/24-word mnemonic seed phrase',
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
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: passwordController,
            obscureText: obscurePassword,
            maxLines: 1,
            decoration: InputDecoration(
              labelText: 'Passphrase (blank if none)',
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
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 8),
          DropdownMenu<Language>(
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
