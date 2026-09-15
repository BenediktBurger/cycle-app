import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Placeholder Statistik screen (Phase 1). Real statistics (arithmetic only,
/// no status conclusions) arrive in Phase 2 (see docs/roadmap.md). No
/// database access.
class StatistikScreen extends StatelessWidget {
  const StatistikScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navStatistik)),
      body: Center(child: Text(l10n.navStatistik)),
    );
  }
}
