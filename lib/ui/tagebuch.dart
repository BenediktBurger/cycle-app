import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Placeholder Tagebuch screen (Phase 1). The real entry form arrives in
/// Phase 2 (see docs/roadmap.md). No database access here.
class TagebuchScreen extends StatelessWidget {
  const TagebuchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navTagebuch)),
      body: Center(child: Text(l10n.navTagebuch)),
    );
  }
}
