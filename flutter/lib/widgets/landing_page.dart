import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'onboarding_stepper_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key, required this.title});
  final String title;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final paragraphs = [
      "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent cursus congue nibh vel aliquet. Suspendisse non est quis felis mollis gravida.",
      "Nam a elit semper massa cursus molestie. Sed viverra sapien nisl, a pharetra arcu malesuada a. Fusce mattis enim sit amet velit venenatis commodo.",
      "Aliquam dictum ornare maximus. Suspendisse molestie varius dignissim. Morbi finibus nulla blandit scelerisque malesuada. Cras arcu diam, sagittis eu sagittis sed, molestie vitae nulla.",
      "Quisque ut libero odio. Nulla fringilla leo diam, nec lacinia odio porta vitae.",
    ].toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            InfoCard(
              imageUrl: 'assets/images/zilliqa-full-teal.svg',
              title: 'Ledger Incident Recovery Proof',
              subTitle: 'Subtitle',
              paragraphs: paragraphs,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OnboardingStepperPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subTitle,
    required this.paragraphs,
  });

  final String imageUrl;
  final String title;
  final String subTitle;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final fullLogo = SvgPicture.asset(imageUrl);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias, // ensures image respects rounded corners
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Horizontal image at the top with 16 padding
          Padding(
            padding: const EdgeInsets.all(32),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: 16 / 5, child: fullLogo),
            ),
          ),

          // Multi-paragraph text body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  subTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 12),
                for (final paragraph in paragraphs) ...[
                  Text(
                    paragraph,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
