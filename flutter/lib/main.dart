import 'package:flutter/material.dart';
import 'package:mopro_flutter_bindings/src/rust/frb_generated.dart';

import 'widgets/landing_page.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const LedgerProofApp());
}

class LedgerProofApp extends StatelessWidget {
  const LedgerProofApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeL = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color.fromRGBO(0, 208, 198, 255),
      ),
    );
    final themeD = ThemeData.dark().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color.fromRGBO(43, 146, 151, 255),
        brightness: Brightness.dark,
      ),
    );
    return MaterialApp(
      title: 'Ledger Incident Recovery Proof',
      theme: themeL,
      darkTheme: themeD,
      themeMode: ThemeMode.system,
      home: const LandingPage(title: 'Ledger Incident'),
    );
  }
}
