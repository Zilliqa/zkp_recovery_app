import 'package:flutter/material.dart';

class InfoCardData {
  final IconData icon;
  final String title;
  final String body;

  const InfoCardData({
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// Placeholder copy - swap in real content later.
const List<InfoCardData> welcomeInfoCards = [
  InfoCardData(
    icon: Icons.info_outline,
    title: 'How this app works',
    body:
        'This app generates a zero-knowledge proof that links your legacy Schnorr-based account to a new EVM-only account.',
  ),
  InfoCardData(
    icon: Icons.security,
    title: 'Your seed phrase stays local',
    body:
        'Your mnemonic seed phrase is only used on-device to compute the proof. It is never transmitted nor stored.',
  ),
  InfoCardData(
    icon: Icons.airplanemode_active,
    title: 'Offline mode capable',
    body:
        'In Step 4, enable Flight mode and disable WiFi for added safety.',
  ),
  InfoCardData(
    icon: Icons.upload_file,
    title: 'Submit the calldata',
    body:
        'In Step 5, copy the calldata and submit it to the Escrow contract.',
  ),
];

class WelcomeStepContent extends StatelessWidget {
  const WelcomeStepContent({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: welcomeInfoCards
          .map(
            (data) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(data.icon, size: 32, color: theme.colorScheme.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(data.body, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
