// Tagebuch screen: daily symptom entry form + the cycle-grouped entry list.
//
// The form writes one day at a time through EntriesDao.upsertDaily (full
// replacement of the day; nulls included). The entry form carries the
// explicit cycle-start switch — the diary-side writer of the authoritative
// cycleStart mark (bleeding never implies or asks for a cycle start here).
// The list underneath groups the live entry stream into cycles using the
// mark-driven boundary rule from lib/domain/cycle_grouping.dart (a cycle
// starts at a user-placed cycleStart mark) and pre-loads the tapped day
// back into the form for editing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/mappers.dart';
import '../domain/cervix.dart';
import '../domain/cycle_grouping.dart';
import '../domain/date_only.dart';
import '../domain/decimal_display.dart';
import '../domain/decimal_input.dart';
import '../domain/marks.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'bleeding_symbol.dart';
import 'mucus_symbol.dart';

class TagebuchScreen extends ConsumerStatefulWidget {
  const TagebuchScreen({super.key});

  @override
  ConsumerState<TagebuchScreen> createState() => _TagebuchScreenState();
}

final class _TagebuchScreenState extends ConsumerState<TagebuchScreen> {
  /// The minimum one-line width that still shows the printed time-field
  /// label next to the temperature field; below it the label drops and the
  /// clock icon carries the meaning (see the narrow-width comment at the
  /// BBT/time row).
  static const double _timeLabelMinLineWidth = 300;

  final _formKey = GlobalKey<FormState>();
  final _bbtController = TextEditingController();
  final _notesController = TextEditingController();

  /// The resolved display locale, captured in [didChangeDependencies] —
  /// entries load async before any build, so the prefill cannot resolve
  /// `Localizations.localeOf` at write time; it reads this cache instead.
  /// ('en' matches MaterialApp's first-supported fallback and is never
  /// observed: the capture above always precedes the first load.)
  String _displayLocale = 'en';

  Bleeding _bleeding = Bleeding.none;
  int _tempDisturbances = 0;
  bool _excludeTemperature = false;
  bool _cycleStartMarked = false;
  TimeOfDay? _measuredAt;
  MucusSign? _sign;
  MucusQuality? _quality;
  CervixPosition? _cervixPosition;
  CervixOpening? _cervixOpening;
  bool _painBreast = false;
  bool _painMittelschmerz = false;
  int _sexTimings = 0;
  CervixFirmness? _cervixFirmness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadEntry(ref.read(selectedDateProvider));
      }
    });
  }

  @override
  void dispose() {
    _bbtController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _displayLocale = Localizations.localeOf(context).toString();
  }

  Future<void> _loadEntry(DateTime date) async {
    final db = await ref.read(databaseProvider.future);
    final existing = await db.entriesDao.entryFor(date);
    // The exclude switch seeds from the day's ACTUAL mark state (not the
    // disturbance mask): an externally placed ignoreTemperature mark —
    // day sheet, imports — shows up as "excluded" in the form. The
    // cycle-start switch seeds the same way from the day's cycleStart
    // mark.
    final dayMarks = await db.marksDao.marksForDay(date);
    final excludeMarked = dayMarks.any(
      (m) => m.markType == CycleMarkTypes.ignoreTemperature,
    );
    final cycleStartMarked = dayMarks.any(
      (m) => m.markType == CycleMarkTypes.cycleStart,
    );
    if (!mounted) return;
    setState(() {
      _applyEntry(
        existing == null ? null : dailyEntryFromDrift(existing),
        excludeMarked,
        cycleStartMarked,
      );
    });
  }

  void _applyEntry(
    DailyEntry? entry,
    bool excludeMarked,
    bool cycleStartMarked,
  ) {
    _bleeding = entry?.bleeding ?? Bleeding.none;
    _tempDisturbances = entry?.tempDisturbances ?? 0;
    _excludeTemperature = excludeMarked;
    _cycleStartMarked = cycleStartMarked;
    // Measured time: a fresh day (nothing stored yet) starts from the
    // CURRENT time as a convenience; a re-opened day keeps what was stored
    // — including deliberately cleared days (stored null), which never
    // re-prefill.
    _measuredAt = entry == null
        ? TimeOfDay.fromDateTime(ref.read(nowProvider)())
        : _minutesToTime(entry.measuredAtMinutes);
    // DailyEntry already enforces quality-only-with-S (constructor assert),
    // so the form state can mirror the loaded pair untouched.
    _sign = entry?.mucusSign;
    _quality = entry?.mucusQuality;
    _cervixPosition = entry?.cervixPosition;
    _cervixOpening = entry?.cervixOpening;
    _cervixFirmness = entry?.cervixFirmness;
    _painBreast = entry?.painBreast ?? false;
    _painMittelschmerz = entry?.painMittelschmerz ?? false;
    _sexTimings = entry?.sexTimings ?? 0;
    final bbt = entry?.bbtC;
    // The prefill follows the display locale ("36,4" in de / "36.4" in en):
    // what the user sees reinstates what she sees elsewhere. Entry stays
    // separator-free by rule — parseDecimalInput accepts BOTH separators,
    // so the comma form saves back identically.
    _bbtController.text = bbt == null
        ? ''
        : formatDecimalPrefill(bbt, locale: _displayLocale);
    _notesController.text = entry?.notes ?? '';
  }

  Future<void> _pickDate() async {
    final selected = ref.read(selectedDateProvider);
    // Window: BBT diaries rarely reach back to 2000; forward only to
    // tomorrow so "I measured just after midnight" still works.
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    ref.read(selectedDateProvider.notifier).state = DateOnly.normalize(picked);
  }

  /// Moves the entry form to the adjacent calendar day ([delta] = -1/+1).
  /// The write goes through [selectedDateProvider], so the existing
  /// `ref.listen` in build reloads the day's entry — exactly the path a
  /// list-tile tap or a chart jump takes. Unsaved edits are discarded by
  /// that reload (the form only persists on the explicit save button),
  /// matching the established semantics of every other day change here.
  void _moveDay(int delta) {
    ref.read(selectedDateProvider.notifier).state = DateOnly.addDays(
      ref.read(selectedDateProvider),
      delta,
    );
  }

  /// Material time picker dialog. Initial value: the stored (or prefilled)
  /// time, or — for still-unset days — the current time as a starting point.
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          _measuredAt ?? TimeOfDay.fromDateTime(ref.read(nowProvider)()),
    );
    if (!mounted || picked == null) return;
    setState(() => _measuredAt = picked);
  }

  /// Minutes since midnight form-state helper, in both directions
  /// ([DailyEntry.measuredAtMinutes] vocabulary and [TimeOfDay] inputs).
  TimeOfDay? _minutesToTime(int? minutes) => minutes == null
      ? null
      : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  static int _timeToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _save(AppLocalizations l10n) async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;
    final date = ref.read(selectedDateProvider);
    // Enforce the domain rule once more at the save boundary: any quality
    // on a sign other than S collapses to null (mirrors the SQL CHECK).
    final (:sign, :quality) = sanitizeMucusPair(sign: _sign, quality: _quality);
    final entry = DailyEntry(
      date: date,
      bbtC: parseDecimalInput(_bbtController.text),
      // The domain model drops a time without a temperature (see
      // DailyEntry.measuredAtMinutes) — the picker row above is only
      // reachable while a temperature is entered, and a temperature that
      // was cleared before saving takes the time with it.
      measuredAtMinutes: _measuredAt == null
          ? null
          : _timeToMinutes(_measuredAt!),
      bleeding: _bleeding,
      tempDisturbances: _tempDisturbances,
      mucusSign: sign,
      mucusQuality: quality,
      cervixPosition: _cervixPosition,
      cervixOpening: _cervixOpening,
      cervixFirmness: _cervixFirmness,
      painBreast: _painBreast,
      painMittelschmerz: _painMittelschmerz,
      // The mask is 0..7 by construction: every chip below toggles exactly
      // one SexTiming bit, so no extra sanitizing is needed here — the
      // DailyEntry constructor assert remains the single guard (same
      // pattern as the mucus-quality save path above).
      sexTimings: _sexTimings,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    final db = await ref.read(databaseProvider.future);
    await db.entriesDao.upsertDaily(entry);
    // The analysis-exclusion mark follows the EXCLUDE SWITCH alone (owner
    // decision 2026-09-19: manual-only coupling — the old flag-driven
    // auto-set is deleted): a flagged save without the switch does not
    // exclude the day, and the switch toggles the mark in BOTH directions
    // (addMark is idempotent, deleteMark no-ops when nothing is there).
    // The switch seeds from the day's existing mark (see _loadEntry), so
    // an untouched switch keeps an externally placed mark (sheet toggle,
    // imports) in place.
    if (_excludeTemperature) {
      await db.marksDao.addMark(date, CycleMarkTypes.ignoreTemperature);
    } else {
      await db.marksDao.deleteMark(date, CycleMarkTypes.ignoreTemperature);
    }
    // The cycleStart mark follows the explicit CYCLE-START SWITCH alone
    // (manual-only coupling — bleeding never implies or asks for a cycle
    // start): the switch toggles the mark in BOTH directions (addMark is
    // idempotent, deleteMark no-ops when nothing is there). The switch
    // seeds from the day's existing mark (see _loadEntry), so an
    // untouched switch keeps an externally placed mark (day sheet,
    // imports) in place.
    if (_cycleStartMarked) {
      await db.marksDao.addMark(date, CycleMarkTypes.cycleStart);
    } else {
      await db.marksDao.deleteMark(date, CycleMarkTypes.cycleStart);
    }
    // No explicit provider invalidation needed: dailyEntriesProvider sits
    // on a drift `.watch()` stream, which re-emits after this write.
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.saved)));
  }

  String _formatDay(DateTime d, String locale) =>
      // The date-only convention is UTC-normalized midnights; DateFormat
      // reads the value's OWN fields, so print it verbatim — a .toLocal()
      // would show the PREVIOUS day on UTC-negative hosts.
      DateFormat.yMd(locale).format(DateOnly.normalize(d));

  // The HEADER date button's label differs from the list date above in
  // two ways, so it gets its own formatter instead of touching _formatDay
  // (whose compact yMd output the cycle-group list and day tiles keep):
  //  1. Mark-sheet style: the longer yMMMEd ("Fr., 10. Apr. 2026") that
  //     the cycle day sheet prints in its header — the two header areas
  //     look and read alike.
  //  2. On today a localized prefix removes the ambiguity between "the
  //     form happens to sit on some date" and "this is today" (todayDate
  //     key). No runtime concatenation: the locale's full composite
  //     ("Heute, Fr., 10. Apr. 2026") lives in the ARB.
  String _headerDayLabel(
    AppLocalizations l10n, {
    required DateTime selected,
    required DateTime now,
    required String locale,
  }) {
    final date =
        // Same verbatim UTC-midnight convention as _formatDay above.
        DateFormat.yMMMEd(locale).format(DateOnly.normalize(selected));
    return DateOnly.sameDay(selected, now) ? l10n.todayDate(date) : date;
  }

  /// Locale-aware two-decimal temperature display ("36,65" in German) —
  /// routed through the shared display formatter (single-sourced like
  /// every other decimal surface).
  String _formatBbt(double bbt, String locale) =>
      formatDecimal(bbt, locale: locale, decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();

    // Cross-screen date changes (chart taps) reload the form fields.
    ref.listen<DateTime>(selectedDateProvider, (previous, next) {
      if (previous == null || !DateOnly.sameDay(previous, next)) {
        _loadEntry(next);
      }
    });

    final entriesAsync = ref.watch(dailyEntriesProvider);
    final selected = ref.watch(selectedDateProvider);
    final marks = ref.watch(marksProvider).valueOrNull ?? const <CycleMark>[];
    // The cycle groups are computed ONCE per build and shared by both
    // consumers — the entry form's day-of-cycle label and the grouped list
    // (which re-used to group the same entries a second time). While the
    // entry stream is still loading there is nothing to group yet.
    final entries = entriesAsync.valueOrNull;
    final cycles = entries == null
        ? const <Cycle>[]
        : groupIntoCycles(
            entries,
            marks,
            // The grouping's injected clock (last-cycle span rule — the
            // nowProvider seam, pinned in tests).
            today: ref.read(nowProvider)(),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navDiary),
        // The Save action lives beside the screen title, so it is reachable
        // from anywhere in the form — not only at the bottom (where the
        // form's bottom button stays available in addition). It calls the
        // same handler, with identical behavior (validation, snackbar, the
        // mark writes).
        actions: [
          IconButton(
            key: const ValueKey('diarySaveAction'),
            icon: const Icon(Icons.save_outlined),
            onPressed: () => _save(l10n),
            tooltip: l10n.save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildForm(l10n, locale, selected, cycles),
          const SizedBox(height: 16),
          ..._buildCycleList(l10n, entriesAsync, cycles),
        ],
      ),
    );
  }

  Widget _buildForm(
    AppLocalizations l10n,
    String locale,
    DateTime selected,
    List<Cycle> cycles,
  ) {
    // The navigation window matches the date picker's (see _pickDate):
    // nothing before 2000, nothing beyond tomorrow ("measured just after
    // midnight") — no unbounded future. "Now" comes from nowProvider so
    // tests can pin the clock.
    final now = ref.watch(nowProvider);
    final previousDay = DateOnly.addDays(selected, -1);
    final nextDay = DateOnly.addDays(selected, 1);
    // The selected day's position in its cycle, 1-based (null before the
    // first group start).
    final selectedCycleDay = dayOfCycleFor(selected, cycles);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- date ---------------------------------------------------
              // Previous/next flank the date button and step through the
              // same window the date picker offers (bounds computed above).
              // Left alignment keeps the date button and the day chevrons together.
              //
              // The date button is flexed so its label constrains to the row
              // instead of overflowing it.
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: previousDay.isBefore(DateTime.utc(2000))
                        ? null
                        : () => _moveDay(-1),
                    tooltip: l10n.entryPreviousDay,
                  ),
                  Flexible(
                    child: OutlinedButton(
                      onPressed: _pickDate,
                      child: Text(
                        _headerDayLabel(
                          l10n,
                          selected: selected,
                          now: now(),
                          locale: locale,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: nextDay.isAfter(DateOnly.addDays(now(), 1))
                        ? null
                        : () => _moveDay(1),
                    tooltip: l10n.entryNextDay,
                  ),
                ],
              ),
              // The day-of-cycle of the SELECTED day, small type in its
              // own line below the navigation row, not inside it: the row
              // already carries the longest label of the form (the
              // yMMMEd date, often with the "Heute, " prefix) and a
              // narrow-width test pins that this label line stays
              // overflow-free (see diary_cycle_day_label_test.dart).
              if (selectedCycleDay != null) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.entryCycleDay(selectedCycleDay),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              // --- BBT + measured time (compact one-line density) --------
              // The measurement time is metadata OF the temperature (the
              // domain model never stores it without one — see
              // DailyEntry.measuredAtMinutes), so the time control shares
              // the temperature's visual line instead of stacking a second
              // row below it. The time control still only shows while a
              // temperature that can actually be saved is entered: the
              // same plausibility gate the validator applies
              // (isWithinBbtRange) — an implausible number like "999"
              // exposes the control just as little as an unparsable one.
              // When it shows, a fresh day is prefilled with the current
              // time (see _applyEntry); explicit clearing sets "not
              // recorded".
              //
              // Narrow content widths (small devices, wide font scaling):
              // the printed "Gemessen um" label is the widest part of the
              // line, so below ~300 dp of form width it drops and the
              // clock icon carries the meaning (the value stays on the
              // button, the clear button stays). A narrow-width test pins
              // that this line stays overflow-free.
              LayoutBuilder(
                builder: (context, lineConstraints) {
                  final showTimeLabel =
                      lineConstraints.maxWidth >= _timeLabelMinLineWidth;
                  return Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('diaryTemperatureField'),
                          controller: _bbtController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: '${l10n.temperature} (°C)',
                          ),
                          validator: (value) {
                            final parsed = parseDecimalInput(value ?? '');
                            if (parsed == null) {
                              return (value ?? '').trim().isEmpty
                                  ? null // temperature stays optional
                                  : l10n.errorTemperature;
                            }
                            return isWithinBbtRange(parsed)
                                ? null
                                : l10n.errorTemperatureRange;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _bbtController,
                        builder: (context, value, _) {
                          final parsed = parseDecimalInput(value.text);
                          if (parsed == null || !isWithinBbtRange(parsed)) {
                            return const SizedBox.shrink();
                          }
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule_outlined),
                              const SizedBox(width: 4),
                              if (showTimeLabel) ...[
                                Text(l10n.measuredTime),
                                const SizedBox(width: 4),
                              ],
                              OutlinedButton(
                                key: const ValueKey('measuredTimeField'),
                                onPressed: _pickTime,
                                child: Text(
                                  _measuredAt == null
                                      ? l10n.measuredTimeUnset
                                      : MaterialLocalizations.of(
                                          context,
                                        ).formatTimeOfDay(_measuredAt!),
                                ),
                              ),
                              if (_measuredAt != null)
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      setState(() => _measuredAt = null),
                                  tooltip: l10n.measuredTimeUnset,
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              // --- temperature disturbance group (flags + exclude switch)
              // One labelled group, one decision (owner decision
              // 2026-09-19: the coupling between the disturbance flags and
              // the analysis exclusion is MANUAL — each flag chip toggles
              // its own bit in the day's tempDisturbances mask — raw data,
              // e.g. the diary list's interrupted-day badge — while the
              // exclude switch is the only diary-side input that writes
              // the ignoreTemperature mark on save). No auto behavior in
              // either direction: flagging never excludes the day, and
              // clearing the flags never lifts an exclusion. The switch
              // seeds from the day's existing mark (see _loadEntry).
              // TODO(user-review): the group wording (heading + switch
              // label) is pending the expert review.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.disturbancesCaption,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final disturbance in TempDisturbance.values)
                          FilterChip(
                            key: ValueKey(
                              'disturbanceChip-${disturbance.name}',
                            ),
                            label: Text(switch (disturbance) {
                              TempDisturbance.sp => l10n.disturbanceLateToBed,
                              TempDisturbance.a =>
                                l10n.disturbanceNightAwakening,
                              TempDisturbance.alk => l10n.disturbanceAlcohol,
                              TempDisturbance.kr => l10n.disturbanceIllness,
                            }),
                            selected: _tempDisturbances & disturbance.bit != 0,
                            onSelected: (selected) => setState(() {
                              _tempDisturbances = selected
                                  ? _tempDisturbances | disturbance.bit
                                  : _tempDisturbances & ~disturbance.bit;
                            }),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      key: const ValueKey('diaryExcludeTemperatureSwitch'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(l10n.diaryExcludeTemperatureSwitch),
                      value: _excludeTemperature,
                      onChanged: (v) => setState(() => _excludeTemperature = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // --- bleeding --------------------------------------------
              // All six levels of the numeric scale, none first. Wrap of
              // ChoiceChips like the mucus quality row below: a six-label
              // SegmentedButton risks overflowing small phone widths.
              Text(l10n.termBleeding),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final bleeding in Bleeding.values)
                    ChoiceChip(
                      key: ValueKey('bleedingChip-${bleeding.name}'),
                      label: Text(switch (bleeding) {
                        Bleeding.none => l10n.bleedingNone,
                        Bleeding.spotting => l10n.bleedingSpotting,
                        Bleeding.light => l10n.bleedingLight,
                        Bleeding.medium => l10n.bleedingMedium,
                        Bleeding.heavy => l10n.bleedingHeavy,
                        Bleeding.maximum => l10n.bleedingMaximum,
                      }),
                      selected: _bleeding == bleeding,
                      onSelected: (selected) => setState(() {
                        // Tapping the selected chip falls back to none,
                        // mirroring the mucus quality chips' toggle.
                        _bleeding = selected ? bleeding : Bleeding.none;
                      }),
                    ),
                ],
              ),
              // --- cycle start ------------------------------------------
              // The explicit cycle-start toggle writes/removes the
              // authoritative cycleStart mark on save — bleeding never
              // implies or asks for a cycle start. Same contract as the
              // exclude switch above: the switch seeds from the day's
              // existing mark (see _loadEntry) and the save mirrors its
              // state in both directions (addMark idempotent, deleteMark
              // no-op). The label reuses the shared "Zyklusbeginn"
              // string.
              SwitchListTile(
                key: const ValueKey('diaryCycleStartSwitch'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.termCycleStart),
                value: _cycleStartMarked,
                onChanged: (v) => setState(() => _cycleStartMarked = v),
              ),
              const SizedBox(height: 12),
              // --- mucus: fertility sign, quality qualifier only on S -----
              // Chips as in the bleeding row above: all six sign options
              // plus the unset chip would divide the width evenly inside a
              // SegmentedButton, and the two-glyph f/S label reflowed to
              // two lines on narrow phone widths (growing the row and
              // painting a partially visible overflow band). The chips show
              // the cheat-sheet glyphs themselves (t/Ø/f/S/A). A quality
              // exists only together with S, so the quality picker appears
              // only while S is selected (hidden otherwise).
              Text(l10n.termMucus),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    key: const ValueKey('mucusSignChip-unset'),
                    label: Text(l10n.mucusSignUnset),
                    selected: _sign == null,
                    onSelected: (_) => setState(() {
                      _sign = null;
                      _quality = null;
                    }),
                  ),
                  for (final sign in MucusSign.values)
                    ChoiceChip(
                      key: ValueKey('mucusSignChip-${sign.name}'),
                      label: Text(mucusSignSymbol(sign)),
                      selected: _sign == sign,
                      onSelected: (selected) => setState(() {
                        _sign = selected ? sign : null;
                        if (_sign != MucusSign.s) _quality = null;
                      }),
                    ),
                ],
              ),
              if (_sign == MucusSign.s) ...[
                const SizedBox(height: 8),
                Text(l10n.mucusQuality),
                const SizedBox(height: 4),
                Wrap(
                  key: const ValueKey('mucusQualityRow'),
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final quality in MucusQuality.values)
                      ChoiceChip(
                        key: ValueKey('mucusQualityChip-${quality.name}'),
                        label: Text(mucusQualityToken(quality)),
                        selected: _quality == quality,
                        onSelected: (selected) => setState(() {
                          // Tapping the selected chip returns to bare S.
                          _quality = selected ? quality : null;
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // --- Muttermund: position (5), opening (3), firmness (3) --
              // All three rows are independent pickers; the leading unset
              // chip ("—") plus the tap-again-deselects rule return to the
              // no-observation state, like the mucus quality chips.
              Text(l10n.termCervixPosition),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text(l10n.cervixPositionUnset),
                    selected: _cervixPosition == null,
                    onSelected: (_) => setState(() => _cervixPosition = null),
                  ),
                  for (final position in CervixPosition.values)
                    ChoiceChip(
                      key: ValueKey('cervixPositionChip-${position.name}'),
                      label: Text(switch (position) {
                        CervixPosition.low => l10n.cervixPositionLow,
                        CervixPosition.medium => l10n.cervixPositionMedium,
                        CervixPosition.high => l10n.cervixPositionHigh,
                        CervixPosition.veryHigh => l10n.cervixPositionVeryHigh,
                        CervixPosition.unreachable =>
                          l10n.cervixPositionUnreachable,
                      }),
                      selected: _cervixPosition == position,
                      onSelected: (selected) => setState(() {
                        _cervixPosition = selected ? position : null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(l10n.cervixOpening),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text(l10n.cervixOpeningUnset),
                    selected: _cervixOpening == null,
                    onSelected: (_) => setState(() => _cervixOpening = null),
                  ),
                  for (final opening in CervixOpening.values)
                    ChoiceChip(
                      key: ValueKey('cervixOpeningChip-${opening.name}'),
                      label: Text(switch (opening) {
                        CervixOpening.closed => l10n.cervixOpeningClosed,
                        CervixOpening.middle => l10n.cervixOpeningMiddle,
                        CervixOpening.open => l10n.cervixOpeningOpen,
                      }),
                      selected: _cervixOpening == opening,
                      onSelected: (selected) => setState(() {
                        _cervixOpening = selected ? opening : null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(l10n.termCervixFirmness),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text(l10n.cervixFirmnessUnset),
                    selected: _cervixFirmness == null,
                    onSelected: (_) => setState(() => _cervixFirmness = null),
                  ),
                  for (final firmness in CervixFirmness.values)
                    ChoiceChip(
                      key: ValueKey('cervixFirmnessChip-${firmness.name}'),
                      label: Text(switch (firmness) {
                        CervixFirmness.hard => l10n.cervixFirmnessHard,
                        CervixFirmness.halfSoft => l10n.cervixFirmnessHalfSoft,
                        CervixFirmness.soft => l10n.cervixFirmnessSoft,
                      }),
                      selected: _cervixFirmness == firmness,
                      onSelected: (selected) => setState(() {
                        _cervixFirmness = selected ? firmness : null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // --- sex times (multi-select) ------------------------------
              // The three time slots are INDEPENDENT toggles: each tap
              // sets/clears its own bit in the day's sexTimings mask and
              // several slots can be selected at once. The mask itself
              // encodes whether sex happened (no bits = not recorded); a
              // time-less "sex happened" is deliberately not representable
              // (see DailyEntry.sexTimings).
              Text(l10n.termSex),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final timing in SexTiming.values)
                    FilterChip(
                      key: ValueKey('sexTimingChip-${timing.name}'),
                      label: Text(switch (timing) {
                        SexTiming.start => l10n.sexTimingStart,
                        SexTiming.middle => l10n.sexTimingMiddle,
                        SexTiming.end => l10n.sexTimingEnd,
                      }),
                      selected: _sexTimings & timing.bit != 0,
                      onSelected: (selected) => setState(() {
                        _sexTimings = selected
                            ? _sexTimings | timing.bit
                            : _sexTimings & ~timing.bit;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // --- pain toggles ----------------------------------------
              Text(l10n.termPain),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilterChip(
                    key: const ValueKey('painChip-breast'),
                    label: Text(l10n.termBreastPain),
                    selected: _painBreast,
                    onSelected: (v) => setState(() => _painBreast = v),
                  ),
                  FilterChip(
                    key: const ValueKey('painChip-mittelschmerz'),
                    label: Text(l10n.termMittelschmerz),
                    selected: _painMittelschmerz,
                    onSelected: (v) => setState(() => _painMittelschmerz = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // --- notes ------------------------------------------------
              TextFormField(
                controller: _notesController,
                maxLines: 4,
                decoration: InputDecoration(labelText: l10n.notes),
              ),
              const SizedBox(height: 12),
              Center(
                child: FilledButton.icon(
                  key: const ValueKey('diarySaveButton'),
                  onPressed: () => _save(l10n),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCycleList(
    AppLocalizations l10n,
    AsyncValue<List<DailyEntry>> entriesAsync,
    List<Cycle> cycles,
  ) {
    return entriesAsync.when(
      loading: () => <Widget>[const SizedBox.shrink()],
      error: (e, s) => <Widget>[Text(l10n.loadFailed)],
      data: (entries) {
        if (entries.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.noEntriesYet,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ];
        }
        // The groups arrive pre-computed from build (see the comment
        // there) — one grouping pass per build, shared with the form.
        return [
          for (var i = cycles.length - 1; i >= 0; i--)
            _cycleTile(l10n, cycles[i], cycles),
        ];
      },
    );
  }

  Widget _cycleTile(AppLocalizations l10n, Cycle cycle, List<Cycle> cycles) {
    final locale = Localizations.localeOf(context).toString();
    // The start label is the opening cycleStart mark's own date for
    // mark-opened cycles — which may sit on an untracked gap day before the
    // first tracked day, so the day count can span untracked gap days too.
    final startLabel = _formatDay(cycle.startDate, locale);
    final endLabel = _formatDay(cycle.endDate, locale);
    final title = cycle.startsAtMenstruation
        ? l10n.cycleGroupOnset(startLabel)
        // Leading group predates the first cycleStart mark: title shows
        // the range END, since the begin is unknown.
        : l10n.cycleGroupLeading(endLabel);
    final dayCount = DateOnly.daysBetween(cycle.endDate, cycle.startDate) + 1;

    return ExpansionTile(
      // Most recent work stays at the top of the list.
      title: Text(title),
      subtitle: Text(l10n.termCycleDays(dayCount)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.cycleTapToEdit,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final day in cycle.days.reversed) _dayTile(l10n, day, cycles),
      ],
    );
  }

  Widget _dayTile(AppLocalizations l10n, DailyEntry day, List<Cycle> cycles) {
    final locale = Localizations.localeOf(context).toString();
    // The day's position inside its cycle, 1-based (null before the first
    // group start) — shown as a small label under the tile's date.
    final cycleDay = dayOfCycleFor(day.date, cycles);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _bleedingMarker(day),
      // The day label block: date, then the small day-of-cycle label —
      // NOT in the trailing row: that row already fills the tile with the
      // widest chip shapes (the recorded narrow-width tile check), and a
      // ListTile lays its trailing out unbounded, so a fixed extra member
      // there would overflow the narrow tile instead of wrapping onto the
      // tile's own second line as this one does.
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatDay(day.date, locale)),
          if (cycleDay != null)
            Text(
              l10n.entryCycleDay(cycleDay),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (day.bbtC != null)
            Text(
              '${_formatBbt(day.bbtC!, locale)} °C',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          // Measured time, subtle: only when recorded that day, small type
          // right after the temperature it belongs to.
          if (day.measuredAtMinutes != null) ...[
            const SizedBox(width: 8),
            Text(
              MaterialLocalizations.of(
                context,
              ).formatTimeOfDay(_minutesToTime(day.measuredAtMinutes!)!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (day.mucusSign != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: MucusSymbolText(
                display: mucusDisplay(
                  sign: day.mucusSign,
                  quality: day.mucusQuality,
                ),
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
          ],
        ],
      ),
      subtitle: day.notes != null
          ? Text(day.notes!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      onTap: () {
        ref.read(selectedDateProvider.notifier).state = DateOnly.normalize(
          day.date,
        );
      },
    );
  }

  Widget _bleedingMarker(DailyEntry day) {
    final scheme = Theme.of(context).colorScheme;
    // The shared square-box bleeding symbol at the tile's 18 px size
    // (bleeding_symbol.dart): a box whose bleed fill is a bottom-anchored
    // fraction of the height, spotting interrupted into dots — the same
    // convention the cycle chart's cells and the glossary sample render.
    final marker = day.bleeding == Bleeding.none
        ? Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              shape: BoxShape.circle,
            ),
          )
        : SizedBox(
            width: 18,
            height: 18,
            child: BleedingSymbol(
              bleeding: day.bleeding,
              color: scheme.error,
              borderColor: scheme.error,
            ),
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        marker,
        // The raw disturbance flags are the interrupted-day rendering
        // signal here (the list tile's little warning badge) — the
        // analysis exclusion is the mark, not this.
        if (day.isInterrupted)
          Positioned(
            right: -6,
            top: -6,
            child: Icon(
              Icons.warning_amber,
              size: 14,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
      ],
    );
  }
}
