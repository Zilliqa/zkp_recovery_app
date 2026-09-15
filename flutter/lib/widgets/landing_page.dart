import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:zkp_recovery_app/widgets/onboarding_stepper_page.dart';

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
      "The older non-EVM side of Zilliqa is retired. This impacts all Schnorr-based accounts and transactions. The current EVM side of Zilliqa is the only way of using the network, going forward. As a result, if your funds are being held in a non-EVM/legacy account, you will no longer be able to access them normally.",
      "In order to regain normal access to your funds, you will need to move your funds from the non-EVM/legacy account over to an EVM account via the Escrow contract - a Smart Contract that exists on the EVM side of the chain, but can receive funds from the non-EVM side of the chain.",
      "Therefore, all existing balances held in a non-EVM Zilliqa account MUST be sent to the Escrow contract. The funds that are thus lodged with the Escrow contract, and recorded against the senders non-EVM/legacy address, can only be claimed by submitting a zero-knowledge proof computed in this app.",
      "The zero-knowledge proof asserts your ownership of the legacy Schnorr-based account by demonstrating your possession of the mnemonic-seed without exposing your mnemonic-seed itself; and binds it to both the non-EVM/legacy account and the new EVM account where the balance will be directed.",
      "Upon confirmation of the proof with the Escrow contract, the funds will be released to the new EVM account.",
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
              title: 'Legacy Account Migration Notice',
              subTitle: 'v0.4.0',
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: AspectRatio(aspectRatio: 16 / 5, child: fullLogo),
                ),
              ),
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
                Text(
                  subTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                // const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
