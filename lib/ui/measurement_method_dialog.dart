// The measurement-method dialog of the Tagebuch screen: which measurement
// route and thermometer name apply from the shown day on. The date line
// shows the day that state is anchored to — the selected day when it
// carries the snapshot itself, the governing snapshot's day while the
// selection only inherits — and, in the inherited case only, navigates the
// diary to that governing day on tap. Save and delete keep acting on the
// selected diary day.
//
// Writes go straight through the MeasurementMethodsDao upsert — no provider
// invalidation, the drift watch stream re-emits on its own.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/mappers.dart';
import '../domain/date_only.dart';
import '../domain/measurement_method.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// Opens the dialog for the diary's currently selected day.
Future<void> showMeasurementMethodDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const MeasurementMethodDialog(),
  );
}

class MeasurementMethodDialog extends ConsumerStatefulWidget {
  const MeasurementMethodDialog({super.key});

  @override
  ConsumerState<MeasurementMethodDialog> createState() =>
      _MeasurementMethodDialogState();
}

class _MeasurementMethodDialogState
    extends ConsumerState<MeasurementMethodDialog> {
  final _thermometer = TextEditingController();

  MeasurementRoute? _route;
  bool _loaded = false;

  /// The load failed — the body shows the failure message, not the
  /// unseeded form.
  bool _loadFailed = false;

  /// The selected day carries its own stored snapshot — the only state that
  /// may be deleted (an inherited method belongs to an earlier day's row).
  bool _dayHasSnapshot = false;

  /// The latest snapshot at or before the selected day — an inheriting
  /// selection shows its date (and navigates to it) instead of the
  /// selected one.
  MeasurementMethodSnapshot? _governing;

  /// No state applies to the selected day at all: the dialog shows the
  /// "not recorded yet" empty state (the first save is the baseline).
  bool _notRecorded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _thermometer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = await ref.read(databaseProvider.future);
      final day = ref.read(selectedDateProvider);
      final snapshots = (await db.measurementMethodsDao.allSnapshots())
          .map(measurementSnapshotFromDrift)
          .toList();
      final effective = effectiveMeasurementMethod(snapshots, day);
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _dayHasSnapshot = snapshots.any((s) => DateOnly.sameDay(s.date, day));
        _governing = effective;
        _route = effective?.route;
        _notRecorded = effective == null;
        _thermometer.text = effective?.thermometer ?? '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadFailed = true;
      });
    }
  }

  /// A failed write leaves the dialog open — nothing was changed, the
  /// success pop stays the only close (mirrors delete_data_card's shape).
  Future<void> _save() async {
    final route = _route;
    if (route == null) return;
    try {
      final db = await ref.read(databaseProvider.future);
      await db.measurementMethodsDao.upsertByDate(
        date: ref.read(selectedDateProvider),
        route: route,
        thermometer: normalizeThermometerName(_thermometer.text),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).saveFailed)),
      );
    }
  }

  Future<void> _delete() async {
    try {
      final db = await ref.read(databaseProvider.future);
      await db.measurementMethodsDao.deleteByDate(
        ref.read(selectedDateProvider),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).deleteDataFailed)),
      );
    }
  }

  /// The tap affordance on the date line sets the diary's selected day to
  /// the governing snapshot's day and closes — the one way this dialog
  /// changes the selection.
  void _navigateToSnapshotDay() {
    final governing = _governing;
    if (governing == null) return;
    ref
        .read(selectedDateProvider.notifier)
        .set(DateOnly.normalize(governing.date));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bodySmall = Theme.of(context).textTheme.bodySmall;
    final locale = Localizations.localeOf(context).toString();
    final selected = ref.watch(selectedDateProvider);
    final navigable =
        _governing != null &&
        !_dayHasSnapshot &&
        !DateOnly.sameDay(_governing!.date, selected);
    final dateLine = Text(
      DateFormat.yMd(
        locale,
      ).format(DateOnly.normalize(_governing?.date ?? selected)),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: navigable ? Theme.of(context).colorScheme.primary : null,
      ),
    );
    return AlertDialog(
      title: Text(l10n.methodDialogTitle),
      content: _loadFailed
          ? Text(l10n.loadFailed)
          : !_loaded
          ? const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (navigable)
                    Tooltip(
                      message: l10n.methodNavigateToChange,
                      child: InkWell(
                        key: const ValueKey('methodDateLine'),
                        onTap: _navigateToSnapshotDay,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: dateLine,
                        ),
                      ),
                    )
                  else
                    dateLine,
                  if (_notRecorded) ...[
                    const SizedBox(height: 4),
                    Text(l10n.methodNotRecorded, style: bodySmall),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final route in MeasurementRoute.values)
                        ChoiceChip(
                          key: ValueKey('methodRouteChip-${route.name}'),
                          label: Text(switch (route) {
                            MeasurementRoute.vaginal => l10n.methodRouteVaginal,
                            MeasurementRoute.rectal => l10n.methodRouteRectal,
                            MeasurementRoute.oral => l10n.methodRouteOral,
                            MeasurementRoute.other => l10n.methodRouteOther,
                          }),
                          selected: _route == route,
                          onSelected: (selected) =>
                              setState(() => _route = selected ? route : null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('methodThermometerField'),
                    controller: _thermometer,
                    decoration: InputDecoration(
                      labelText: l10n.methodThermometerLabel,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.methodHelperText, style: bodySmall),
                  const SizedBox(height: 4),
                  Text(l10n.methodChangeNote, style: bodySmall),
                ],
              ),
            ),
      actions: [
        if (_dayHasSnapshot)
          TextButton(
            key: const ValueKey('methodDeleteButton'),
            onPressed: _delete,
            child: Text(l10n.methodDeleteChange),
          ),
        FilledButton(
          key: const ValueKey('methodSaveButton'),
          onPressed: _route == null ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
