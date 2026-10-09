// Tagebuch screen: the daily entry form plus the cycle-grouped entry
// list. The form writes one day at a time (EntriesDao.upsertDaily, full
// replacement of the day — nulls included) and carries the explicit
// manual-only exclude/cycle-start switches (rationale at the _save writes).
// The list groups the live entry stream by the mark-driven boundary rule
// from lib/domain/cycle_grouping.dart (a cycle starts at a user-placed
// cycleStart mark) and pre-loads the tapped day back into the form.
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
import 'stream_error.dart';

class TagebuchScreen extends ConsumerStatefulWidget {
  const TagebuchScreen({super.key});

  @override
  ConsumerState<TagebuchScreen> createState() => _TagebuchScreenState();
}

final class _TagebuchScreenState extends ConsumerState<TagebuchScreen> {
  /// The minimum one-line width that still shows the printed time-field
  /// label next to the temperature field; below it the label drops and
  /// the clock icon carries the meaning (see the narrow-width note at
  /// the BBT/time row).
  static const double _timeLabelMinLineWidth = 300;

  final _formKey = GlobalKey<FormState>();
  final _bbtController = TextEditingController();
  final _notesController = TextEditingController();

  /// The resolved display locale, captured in [didChangeDependencies]:
  /// entries load async before any build, so the prefill cannot resolve
  /// the locale at write time and reads this cache instead.
  String _displayLocale = 'en';

  /// The cycles whose day list is currently expanded, keyed by the
  /// normalized cycle start date. Widget state: expansions survive the
  /// list's data-driven rebuilds but not leaving the screen.
  final Set<DateTime> _expandedCycleStarts = <DateTime>{};

  Bleeding _bleeding = Bleeding.none;
  int _tempDisturbances = 0;
  bool _excludeTemperature = false;
  bool _cycleStartMarked = false;
  TimeOfDay? _measuredAt;
  MucusSign? _sign;
  MucusQuality? _quality;

  /// True while [_applyEntry] seeds [_bbtController]: the stamp listener
  /// must ignore that notification.
  bool _suppressBbtStamp = false;

  CervixPosition? _cervixPosition;
  CervixOpening? _cervixOpening;
  bool _painBreast = false;
  bool _painMittelschmerz = false;
  int _sexTimings = 0;
  CervixFirmness? _cervixFirmness;

  @override
  void initState() {
    super.initState();
    _bbtController.addListener(_onBbtChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadEntry(ref.read(selectedDateProvider));
      }
    });
  }

  @override
  void dispose() {
    _bbtController.removeListener(_onBbtChanged);
    _bbtController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _displayLocale = Localizations.localeOf(context).toString();
  }

  /// Entering a valid, in-range temperature stamps the current time while
  /// the day is today and no time is in the form yet — a seeded (loaded)
  /// temperature is a fact of the stored day, not an entry event.
  void _onBbtChanged() {
    if (_suppressBbtStamp || !mounted) return;
    final parsed = parseDecimalInput(_bbtController.text);
    final now = ref.read(nowProvider)();
    if (parsed == null ||
        !isWithinBbtRange(parsed) ||
        _measuredAt != null ||
        !DateOnly.sameDay(ref.read(selectedDateProvider), now)) {
      return;
    }
    setState(() => _measuredAt = TimeOfDay.fromDateTime(now));
  }

  Future<void> _loadEntry(DateTime date) async {
    final db = await ref.read(databaseProvider.future);
    final existing = await db.entriesDao.entryFor(date);
    // The switches seed from the day's ACTUAL mark state, so marks placed
    // elsewhere (day sheet, imports) show up in the form.
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
    _measuredAt = _minutesToTime(entry?.measuredAtMinutes);
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
    // The prefill follows the display locale ("36,4" in de / "36.4" in
    // en); parseDecimalInput accepts both separators, so the comma form
    // saves back identically.
    _suppressBbtStamp = true;
    _bbtController.text = bbt == null
        ? ''
        : formatDecimalPrefill(bbt, locale: _displayLocale);
    _suppressBbtStamp = false;
    _notesController.text = entry?.notes ?? '';
  }

  Future<void> _pickDate() async {
    final selected = ref.read(selectedDateProvider);
    // Back only to 2000 (BBT diaries rarely reach further); forward to
    // tomorrow so "I measured just after midnight" still works.
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    ref.read(selectedDateProvider.notifier).set(DateOnly.normalize(picked));
  }

  /// Moves the entry form to the adjacent calendar day through
  /// [selectedDateProvider], so the existing `ref.listen` in build
  /// reloads the day — and unsaved edits are discarded by that reload,
  /// like every other day change here.
  void _moveDay(int delta) {
    ref
        .read(selectedDateProvider.notifier)
        .set(DateOnly.addDays(ref.read(selectedDateProvider), delta));
  }

  /// Time picker seeded from the form's time; without one it falls back
  /// to the current time.
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          _measuredAt ?? TimeOfDay.fromDateTime(ref.read(nowProvider)()),
    );
    if (!mounted || picked == null) return;
    setState(() => _measuredAt = picked);
  }

  /// Minutes-since-midnight ↔ [TimeOfDay] helper
  /// ([DailyEntry.measuredAtMinutes] vocabulary).
  TimeOfDay? _minutesToTime(int? minutes) => minutes == null
      ? null
      : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  static int _timeToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _save(AppLocalizations l10n) async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;
    final date = ref.read(selectedDateProvider);
    // Enforce the domain rule once more at the save boundary: a quality on
    // a sign other than S collapses to null (mirrors the SQL CHECK).
    final (:sign, :quality) = sanitizeMucusPair(sign: _sign, quality: _quality);
    final entry = DailyEntry(
      date: date,
      bbtC: parseDecimalInput(_bbtController.text),
      // The domain model drops a time without a temperature (see
      // DailyEntry.measuredAtMinutes) — clearing the temperature takes
      // the time with it.
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
      // The mask is 0..7 by construction (each chip toggles exactly one
      // bit); the DailyEntry constructor assert is the single guard.
      sexTimings: _sexTimings,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    try {
      final db = await ref.read(databaseProvider.future);
      // The three writes are ONE transaction: a day is stored either
      // completely or not at all.
      await db.transaction(() async {
        await db.entriesDao.upsertDaily(entry);
        // The exclusion mark follows the EXCLUDE SWITCH alone (owner
        // decision 2026-09-19: manual coupling — a flagged save without
        // the switch does not exclude the day); the switch toggles in
        // both directions and seeds from the existing mark (_loadEntry),
        // so an untouched switch keeps an externally placed mark.
        if (_excludeTemperature) {
          await db.marksDao.addMark(date, CycleMarkTypes.ignoreTemperature);
        } else {
          await db.marksDao.deleteMark(date, CycleMarkTypes.ignoreTemperature);
        }
        // Same manual coupling as the exclude switch above — bleeding
        // never implies or asks for a cycle start.
        if (_cycleStartMarked) {
          await db.marksDao.addMark(date, CycleMarkTypes.cycleStart);
        } else {
          await db.marksDao.deleteMark(date, CycleMarkTypes.cycleStart);
        }
      });
    } catch (_) {
      // The transaction rolled back — nothing changed; report the failure
      // instead of leaking an unhandled async error.
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.saveFailed)));
      return;
    }
    // No provider invalidation: dailyEntriesProvider's drift watch stream
    // re-emits after this write.
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.saved)));
  }

  String _formatDay(DateTime d, String locale) =>
      // Date-only values are UTC-normalized midnights — print verbatim;
      // a .toLocal() shows the previous day on UTC-negative hosts.
      DateFormat.yMd(locale).format(DateOnly.normalize(d));

  // The HEADER date button gets its own formatter (the list keeps the
  // compact yMd output): the longer yMMMEd style the cycle day sheet's
  // header prints, plus a localized "Heute, " prefix on today — the full
  // composite lives in the ARB, not a runtime concatenation.
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
    // The marks watch stays unmasked: a failed stream must surface in the
    // cycle-list area below instead of rendering a silently empty list.
    final marksAsync = ref.watch(marksProvider);
    // The cycle groups come from the shared derived pass behind
    // derivedCycleDataProvider — no per-build grouping here.
    final cycles = ref.watch(derivedCycleDataProvider).cycles;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navDiary),
        // The Save action beside the screen title stays reachable from
        // anywhere in the form (the bottom button remains in addition);
        // it calls the same handler.
        actions: [
          IconButton(
            key: const ValueKey('diarySaveAction'),
            icon: const Icon(Icons.save_outlined),
            onPressed: () => _save(l10n),
            tooltip: l10n.save,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverToBoxAdapter(
              child: _buildForm(l10n, locale, selected, cycles),
            ),
          ),
          // A marks error takes precedence: only a healthy marks stream
          // lets the entries-driven list render.
          if (marksAsync.hasError)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              sliver: SliverToBoxAdapter(
                child: StreamLoadError(
                  scope: 'marks',
                  onRetry: () => ref.invalidate(marksProvider),
                ),
              ),
            )
          else
            ..._buildCycleSlivers(l10n, entriesAsync, cycles),
          const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
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
    // Same navigation window as the date picker: nothing before 2000,
    // nothing beyond tomorrow. "Now" comes from nowProvider so tests can
    // pin the clock.
    final now = ref.watch(nowProvider);
    final previousDay = DateOnly.addDays(selected, -1);
    final nextDay = DateOnly.addDays(selected, 1);
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
              // The chevrons step the same window the date picker offers,
              // and the flexed date button keeps its label inside the row.
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
              // The day-of-cycle of the SELECTED day, small type on its
              // own line: the navigation row already carries the form's
              // longest label, and a narrow-width test pins this line
              // overflow-free (diary_cycle_day_label_test.dart).
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
              // domain model never stores it without one, see
              // DailyEntry.measuredAtMinutes), so the time control shares
              // the temperature's visual line and shows only while a
              // savable temperature is entered — the same range gate the
              // validator applies. Entering the temperature on today
              // stamps the current time (see _onBbtChanged).
              //
              // Narrow content widths (small devices, wide font scaling):
              // below ~300 dp of form width the printed label drops and
              // the clock icon carries the meaning; a narrow-width test
              // pins that this line stays overflow-free.
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
              // The flag chips toggle raw tempDisturbances bits
              // (interrupted-day data); the exclude switch is the only
              // diary-side input that writes the ignoreTemperature mark on
              // save (manual-only coupling — see _save).
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
              // Wrap of ChoiceChips: a six-label SegmentedButton risks
              // overflowing small phone widths.
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
              // The explicit toggle writes/removes the authoritative
              // cycleStart mark on save — bleeding never implies or asks
              // for a cycle start; same manual coupling as the exclude
              // switch above.
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
              // Chips as in the bleeding row: a SegmentedButton reflowed
              // the two-glyph labels to two lines on narrow phone widths
              // (an overflow band). The chips show the cheat-sheet glyphs
              // (t/Ø/f/S/A) themselves; a quality exists only together
              // with S, so the quality picker appears only while S is
              // selected.
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
                      tooltip: mucusSignTooltip(sign, l10n),
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
                        tooltip: mucusQualityTooltip(quality, l10n),
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
              // Independent pickers; the unset chip plus the
              // tap-again-deselect rule returns to the no-observation
              // state, like the mucus quality chips.
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
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cervixOpeningSymbol(opening)!),
                          const SizedBox(width: 4),
                          Text(switch (opening) {
                            CervixOpening.closed => l10n.cervixOpeningClosed,
                            CervixOpening.middle => l10n.cervixOpeningMiddle,
                            CervixOpening.open => l10n.cervixOpeningOpen,
                          }),
                        ],
                      ),
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
              // Independent toggles: each tap sets/clears its own bit,
              // several slots at once. No bits = not recorded — a time-less
              // "sex happened" is deliberately not representable (see
              // DailyEntry.sexTimings).
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
                        SexTiming.morning => l10n.sexTimingMorning,
                        SexTiming.midday => l10n.sexTimingMidday,
                        SexTiming.evening => l10n.sexTimingEvening,
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

  List<Widget> _buildCycleSlivers(
    AppLocalizations l10n,
    AsyncValue<List<DailyEntry>> entriesAsync,
    List<Cycle> cycles,
  ) {
    return entriesAsync.when(
      loading: () => const <Widget>[],
      error: (e, s) => <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverToBoxAdapter(
            child: StreamLoadError(
              scope: 'entries',
              onRetry: () => ref.invalidate(dailyEntriesProvider),
            ),
          ),
        ),
      ],
      data: (entries) {
        if (entries.isEmpty) {
          return [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    l10n.noEntriesYet,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
          ];
        }
        // The groups arrive pre-computed from the shared derived pass;
        // the list walks them most recent first.
        return [
          for (var i = cycles.length - 1; i >= 0; i--)
            ..._cycleSlivers(l10n, cycles[i]),
        ];
      },
    );
  }

  /// One cycle as slivers: the header tile plus — only while expanded —
  /// the lazily-built day list. The day rows deliberately do NOT live
  /// inside the header tile as [ExpansionTile] children: an expanded tile
  /// builds its whole children column in one pass, so a cycle spanning
  /// years would construct every tile on the first expansion; the sliver
  /// list below builds only the rows the viewport lays out.
  List<Widget> _cycleSlivers(AppLocalizations l10n, Cycle cycle) {
    final start = DateOnly.normalize(cycle.startDate);
    final expanded = _expandedCycleStarts.contains(start);
    final spanDays = cycleSpanDays(cycle);
    return [
      // Stable keys: sibling expand/collapse shifts these slivers' positions
      // and positional reconciliation would remount the neighboring header,
      // resetting its tile state.
      SliverPadding(
        key: ValueKey('cycle-header-${start.toIso8601String()}'),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverToBoxAdapter(
          child: _cycleHeader(l10n, cycle, initiallyExpanded: expanded),
        ),
      ),
      if (expanded)
        SliverPadding(
          key: ValueKey('cycle-days-${start.toIso8601String()}'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList.builder(
            // Index 0 carries the tap-to-edit caption; indexes 1.. walk the
            // cycle's span days newest first.
            itemCount: spanDays.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.cycleTapToEdit,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              return _dayTile(l10n, spanDays[spanDays.length - index], cycle);
            },
          ),
        ),
    ];
  }

  /// [initiallyExpanded] restores the set's state only on a remounted tile;
  /// [_expandedCycleStarts] stays the source of truth via [onExpansionChanged].
  Widget _cycleHeader(
    AppLocalizations l10n,
    Cycle cycle, {
    required bool initiallyExpanded,
  }) {
    // The start label is the opening cycleStart mark's own date for
    // mark-opened cycles — which may sit on an untracked gap day before
    // the first tracked day, so the day count can span untracked gap
    // days too.
    final locale = Localizations.localeOf(context).toString();
    final startLabel = _formatDay(cycle.startDate, locale);
    final endLabel = _formatDay(cycle.endDate, locale);
    final title = cycle.startsAtMark
        ? l10n.cycleGroupOnset(startLabel)
        // The leading group predates the first cycleStart mark, so the
        // range END stands in the title (the begin is unknown).
        : l10n.cycleGroupLeading(endLabel);
    // The count reports the cycle's TRUE calendar span (silent gaps
    // included), even where the list shows only the built portion.
    final dayCount = DateOnly.daysBetween(cycle.endDate, cycle.startDate) + 1;

    return ExpansionTile(
      // The key anchors the expansion state to THIS cycle across the
      // list's data-driven rebuilds, in sync with _expandedCycleStarts.
      key: ValueKey(DateOnly.normalize(cycle.startDate)),
      initiallyExpanded: initiallyExpanded,
      title: Text(title),
      subtitle: Text(l10n.termCycleDays(dayCount)),
      onExpansionChanged: (isExpanded) => setState(() {
        if (isExpanded) {
          _expandedCycleStarts.add(DateOnly.normalize(cycle.startDate));
        } else {
          _expandedCycleStarts.remove(DateOnly.normalize(cycle.startDate));
        }
      }),
    );
  }

  Widget _dayTile(AppLocalizations l10n, DailyEntry day, Cycle cycle) {
    final locale = Localizations.localeOf(context).toString();
    // The day's position inside its cycle, 1-based — [cycle] itself is
    // the containing cycle: a day of the list never falls beyond the next
    // cycle's start.
    final cycleDay = dayOfCycleFor(day.date, [cycle]);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _bleedingMarker(day),
      // The label block sits in the title, not the trailing row: the
      // trailing already fills the narrow tile (the recorded narrow-width
      // tile check), and a ListTile lays its trailing out unbounded.
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
                sign: day.mucusSign,
                quality: day.mucusQuality,
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
        ref
            .read(selectedDateProvider.notifier)
            .set(DateOnly.normalize(day.date));
      },
    );
  }

  Widget _bleedingMarker(DailyEntry day) {
    final scheme = Theme.of(context).colorScheme;
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
        // The interrupted-day badge reads the RAW disturbance flags —
        // the analysis exclusion is the ignoreTemperature mark, not this.
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
