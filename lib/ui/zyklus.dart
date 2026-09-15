import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Placeholder Zyklus screen (Phase 1). The temperature curve (fl_chart)
/// arrives in Phase 2 (see docs/roadmap.md). No database access here.
class ZyklusScreen extends StatelessWidget {
  const ZyklusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navZyklus)),
      body: Center(child: Text(l10n.navZyklus)),
    );
  }
}
