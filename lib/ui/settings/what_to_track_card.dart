import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/diary_track.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// The settings card for the diary form's section visibility: one switch
// per tracked item.
final class WhatToTrackCard extends ConsumerWidget {
  const WhatToTrackCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final track = ref.watch(diaryTrackProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsTrackTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final item in DiaryItem.values)
              SwitchListTile(
                key: ValueKey('trackSwitch-${item.name}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_itemLabel(item, l10n)),
                value: track.isTracked(item),
                onChanged: (tracked) {
                  ref
                      .read(diaryTrackProvider.notifier)
                      .set(track.withTracked(item, tracked));
                },
              ),
          ],
        ),
      ),
    );
  }

  String _itemLabel(DiaryItem item, AppLocalizations l10n) => switch (item) {
    DiaryItem.mucus => l10n.settingsTrackMucus,
    DiaryItem.cervix => l10n.settingsTrackCervix,
    DiaryItem.sex => l10n.settingsTrackSex,
    DiaryItem.pain => l10n.settingsTrackPain,
  };
}
