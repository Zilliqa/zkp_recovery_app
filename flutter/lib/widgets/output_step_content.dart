import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OutputStepContent extends StatelessWidget {
  final String? result;

  const OutputStepContent({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = this.result;

    if (result == null) {
      return Text(
        'Complete the previous step to generate your proof.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send your entire legacy balance to the Escrow contract, published at the address below, using the legacy Schnorr wallet.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const _CopyableField(
          label: 'Contract address',
          value: '0x00000000005A494c31455343524f5750524f5859', // hard-coded
        ),
        const SizedBox(height: 16),
        Text(
          'To claim your funds, copy and paste the calldata / bytes argument into your EVM wallet, and submit it to the Escrow contract at the address below.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _CopyableField(label: 'Contract calldata', value: result),
        const SizedBox(height: 16),
        const _CopyableField(
          label: 'Contract address',
          value: '0x00000000005A494c31455343524f5750524f5859', // hard-coded
        ),
        const SizedBox(height: 16),
        Text(
          'For added safety, you may remove this app and restart this device after submitting the proof.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}

class _CopyableField extends StatelessWidget {
  final String label;
  final String value;

  const _CopyableField({required this.label, required this.value});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: TextEditingController(text: value),
          readOnly: true,
          minLines: 1,
          maxLines: 10,
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.highlightColor,
            border: const OutlineInputBorder(borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(10),
            suffixIcon: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: () => _copy(context),
            ),
            counterText: label,
          ),
        ),
      ],
    );
  }
}
