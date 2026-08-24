import 'package:flutter/material.dart';

class ChecklistItemData {
  final String title;
  final String subtitle;

  const ChecklistItemData({required this.title, required this.subtitle});
}

/// Placeholder copy - swap in real content later.
const List<ChecklistItemData> prepChecklistItems = [
  ChecklistItemData(
    title: 'Mnemonic seed phrase',
    subtitle:
        'Have your mnemonic-seed ready to type in - you will need it in a later step.',
  ),
  ChecklistItemData(
    title: 'Fresh EVM-only account',
    subtitle:
        'Have a EVM-only account ready - this new account will be the destination for your funds.',
  ),
  ChecklistItemData(
    title: 'Agree to Terms of Use',
    subtitle:
        'You are deemed to have agreed to terms of use at https://www.zilliqa.com/ledger-incident/',
  ),
];

class ChecklistStepContent extends StatelessWidget {
  final List<bool> checkedFlags;
  final ValueChanged<int> onToggle;

  const ChecklistStepContent({
    super.key,
    required this.checkedFlags,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allChecked = checkedFlags.every((c) => c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: List.generate(prepChecklistItems.length, (index) {
                final item = prepChecklistItems[index];
                return CheckboxListTile(
                  value: checkedFlags[index],
                  onChanged: (_) => onToggle(index),
                  title: Text(item.title),
                  subtitle: Text(item.subtitle),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),
            ),
          ),
        ),
        if (!allChecked) ...[
          const SizedBox(height: 8),
          Text(
            'Please confirm both steps above to continue.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
