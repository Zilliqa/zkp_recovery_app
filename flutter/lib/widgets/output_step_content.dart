import 'package:flutter/material.dart';

import '../../services/proof_service.dart';

class OutputStepContent extends StatelessWidget {
  final ProofResult? result;

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

        _HexPreview(hex: result.abiEncodedHex),
        const SizedBox(height: 8),
        Text(
          'Copy and paste this directly as calldata / bytes argument in your wallet. Submit it to the published contract at\n\n0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _HexPreview extends StatelessWidget {
  final String hex;
  const _HexPreview({required this.hex});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        hex,
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
