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
      "This Notice is issued by Zilliqa in relation to the Zero Knowledge Migration App to facilitate migration of \$ZILs held in a non-EVM Schnorr-based legacy accounts (\"Legacy Account\") to EVM based accounts (\"EVM Account\"). This Notice is applicable to you if you hold \$ZILs in a Legacy Account and you must read this Notice carefully before proceeding to use the Migration App to move your \$ZIL from your Legacy Account to a EVM Account designated (\"Designated EVM Account\") by you.",
      "The older non-EVM side of Zilliqa is retired. This impacts all Legacy Accounts and transactions. The current EVM side of Zilliqa is the only way of using the network, going forward. As a result, if your \$ZILs are being held in a Legacy Account, you will no longer be able to access them.",
      "In order to regain access to your \$ZILs that are in your Legacy Account, you MUST move ALL AND NOT PART OF your \$ZILs from your Legacy Acount over to your designated EVM account via the Escrow Contract - a Smart Contract that exists on the EVM side of the chain, but can receive your \$ZILs from the non-EVM side of the chain.",
      "To initiate the move of your \$ZILs from your Legacy Account to your designated EVM Account, you MUST send ALL AND NOT PART OF your \$ZILs from your Legacy Account to the Escrow Contract to lodge your \$ZILs with the Escrow Contract which will be recorded against your Legacy Account address. Thereafter, you can claim your \$ZILs from the Escrow Contract to your designated EVM Account by submitting to the Escrow Contract, the calldata associated with a zero-knowledge proof that you create using this Migration App.",
      "The zero-knowledge proof constitutes proof of your ownership of your Legacy Account by demonstrating your possession of the mnemonic-seed to your Legacy Account without exposing that mnemonic-seed, and binds the mnemonic-seed to both your Legacy Account and your designated EVM Account.",
      "Following your submission of that zero-knowledge proof calldata to and confirmation of that calldata with the Escrow Contract, the Escrow Contract will initiate the release of your \$ZILs that you had lodged with the Escrow Contract to your designated EVM account."
      // "The designated EVM Account MUST be derived using a separate private key from that used to derive the Legacy Account.",
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
              subTitle: 'v0.5.0',
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
                for (final entry in paragraphs.asMap().entries) ...[
                  Text(
                    entry.value,
                    style: entry.key == 0
                        ? Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: Colors.red)
                        : Theme.of(context).textTheme.bodyMedium,
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
