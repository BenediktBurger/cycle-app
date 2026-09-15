import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Placeholder Einstellungen screen (Phase 1). Language switcher, PIN lock
/// stub (ADR-005) and JSON export/import arrive in Phase 2 (see
/// docs/roadmap.md).
/// No database access here.
class EinstellungenScreen extends StatelessWidget {
  const EinstellungenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navEinstellungen)),
      body: Center(child: Text(l10n.navEinstellungen)),
    );
  }
}
