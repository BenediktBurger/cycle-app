// Einstellungen screen: language and theme-mode switchers, the
// temperature range, paper history, the PIN-lock stub (ADR-0005), JSON
// export/import, PDF export and the drip CSV import.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'about.dart';
import 'settings/delete_data_card.dart';
import 'settings/drip_import_card.dart';
import 'settings/export_import_card.dart';
import 'settings/general_info_card.dart';
import 'settings/locale_card.dart';
import 'settings/paper_history_card.dart';
import 'settings/pdf_export_card.dart';
import 'settings/temperature_range_card.dart';
import 'settings/theme_card.dart';

export 'settings/export_import_card.dart' show exportFileName;

class EinstellungenScreen extends ConsumerWidget {
  const EinstellungenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navSettings),
        actions: [
          // The about page plays the SAME content the first-start
          // onboarding shows (lib/ui/about.dart) — one content source,
          // opened on demand.
          IconButton(
            key: const ValueKey('aboutAction'),
            icon: const Icon(Icons.info_outline),
            tooltip: l10n.aboutShow,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (context) => const AboutPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const GeneralInfoCard(),
          const SizedBox(height: 8),
          const PaperHistoryCard(),
          const SizedBox(height: 8),
          const LanguageCard(),
          const SizedBox(height: 8),
          const ThemeModeCard(),
          const SizedBox(height: 8),
          const TemperatureRangeCard(),
          const SizedBox(height: 8),
          // --- PIN lock stub -------------------------------------------
          // Disabled ON PURPOSE: flipping it on would falsely signal that a
          // lock exists (at-rest encryption is already always-on on
          // native, ADR-005; the user-facing lock story is open).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    value: false,
                    onChanged: null,
                    title: Text(l10n.settingsPinLock),
                  ),
                  Text(
                    l10n.settingsPinLockNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const ExportImportCard(),
          const SizedBox(height: 8),
          const PdfExportCard(),
          const SizedBox(height: 8),
          const DripImportCard(),
          const SizedBox(height: 8),
          const DeleteDataCard(),
          const SizedBox(height: 8),
          // --- feedback note -------------------------------------------
          // The pane's compact closing line (the about page carries the
          // same stance as its footer): the app does not send anything,
          // so errors/suggestions go to the GitHub issue tracker or mail.
          Text(
            l10n.settingsFeedbackNotice,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
