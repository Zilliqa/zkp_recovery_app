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
    title: 'New designated EVM Account',
    subtitle:
        'Have your designated EVM Account ready - this EVM-only account will be the destination for your funds.',
  ),
  ChecklistItemData(
    title: 'Agree to terms of use of Migration App',
    subtitle:
        'By ticking off on this checkbox, you confirm your agreement to and to be bound by the terms of the GPLv3 accessible https://www.gnu.org/licenses/gpl-3.0.html which shall apply to your use of the Migration App.',
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
            'Please confirm all requirements above to continue.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
