// Tagebuch screen: daily symptom entry form + the cycle-grouped entry list.
//
// The form writes one day at a time through EntriesDao.upsertDaily (full
// replacement of the day; nulls included). The list underneath groups the
// live entry stream into cycles using the boundary rule from
// lib/domain/cycle_grouping.dart (assumption pending expert review) and
// pre-loads the tapped day back into the form for editing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../db/mappers.dart';
import '../domain/cycle_grouping.dart';
import '../domain/date_only.dart';
import '../domain/decimal_input.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

class TagebuchScreen extends ConsumerStatefulWidget {
  const TagebuchScreen({super.key});

  @override
  ConsumerState<TagebuchScreen> createState() => _TagebuchScreenState();
}

final class _TagebuchScreenState extends ConsumerState<TagebuchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bbtController = TextEditingController();
  final _cervixController = TextEditingController();
  final _notesController = TextEditingController();

  Bleeding _bleeding = Bleeding.none;
  bool _excludeIllness = false;
  bool _excludeAlcohol = false;
  bool _excludeTravel = false;
  bool _excludeOther = false;
  MucusFeeling? _feeling;
  int? _mucusNfp;
  bool _pain = false;
  bool _mood = false;
  bool _desire = false;
  bool _sex = false;

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
    _cervixController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEntry(DateTime date) async {
    final db = await ref.read(databaseProvider.future);
    final existing = await db.entriesDao.entryFor(defaultProfileId, date);
    if (!mounted) return;
    setState(() {
      _applyEntry(existing == null ? null : dailyEntryFromDrift(existing));
    });
  }

  void _applyEntry(DailyEntry? entry) {
    _bleeding = entry?.bleeding ?? Bleeding.none;
    _excludeIllness = entry?.excludeIllness ?? false;
    _excludeAlcohol = entry?.excludeAlcohol ?? false;
    _excludeTravel = entry?.excludeTravel ?? false;
    _excludeOther = entry?.excludeOther ?? false;
    _feeling = entry?.mucusFeeling == null
        ? null
        : MucusFeeling.tryFromName(entry!.mucusFeeling!);
    _mucusNfp = entry?.mucusNfp;
    _pain = entry?.pain ?? false;
    _mood = entry?.mood ?? false;
    _desire = entry?.desire ?? false;
    _sex = entry?.sex ?? false;
    final bbt = entry?.bbtC;
    _bbtController.text = bbt == null ? '' : bbt.toString();
    _cervixController.text = entry?.cervix ?? '';
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

  Future<void> _save(AppLocalizations l10n) async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;
    final date = ref.read(selectedDateProvider);
    final entry = DailyEntry(
      date: date,
      profileId: defaultProfileId,
      bbtC: parseDecimalInput(_bbtController.text),
      bleeding: _bleeding,
      excludeIllness: _excludeIllness,
      excludeAlcohol: _excludeAlcohol,
      excludeTravel: _excludeTravel,
      excludeOther: _excludeOther,
      mucusFeeling: _feeling?.name,
      mucusNfp: _mucusNfp,
      cervix: _cervixController.text.trim().isEmpty
          ? null
          : _cervixController.text.trim(),
      pain: _pain,
      mood: _mood,
      desire: _desire,
      sex: _sex,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );
    final db = await ref.read(databaseProvider.future);
    await db.entriesDao.upsertDaily(entry);
    // No explicit provider invalidation needed: dailyEntriesProvider sits
    // on a drift `.watch()` stream, which re-emits after this write.
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.saved)));
  }

  String _formatDay(DateTime d, String locale) =>
      DateFormat.yMd(locale).format(DateOnly.normalize(d).toLocal());

  /// Locale-aware two-decimal temperature display ("36,65" in German).
  String _formatBbt(double bbt, String locale) =>
      NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: 2,
      ).format(bbt);

  String _feelingLabel(MucusFeeling f, AppLocalizations l10n) {
    switch (f) {
      case MucusFeeling.dry:
        return l10n.mucusDry;
      case MucusFeeling.sticky:
        return l10n.mucusSticky;
      case MucusFeeling.creamy:
        return l10n.mucusCreamy;
      case MucusFeeling.moist:
        return l10n.mucusMoist;
      case MucusFeeling.wet:
        return l10n.mucusWet;
      case MucusFeeling.stretchy:
        return l10n.mucusStretchy;
    }
  }

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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navTagebuch)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildForm(l10n, locale, selected),
          const SizedBox(height: 16),
          ..._buildCycleList(l10n, entriesAsync),
        ],
      ),
    );
  }

  Widget _buildForm(
    AppLocalizations l10n,
    String locale,
    DateTime selected,
  ) {
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
              Row(
                children: [
                  const Icon(Icons.event_outlined),
                  const SizedBox(width: 8),
                  Text(l10n.entryDate),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _pickDate,
                    child: Text(_formatDay(selected, locale)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // --- BBT -------------------------------------------------
              TextFormField(
                controller: _bbtController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${l10n.temperature} (°C)',
                  helperText: '36,6 · 36.65',
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
              const SizedBox(height: 12),
              // --- bleeding --------------------------------------------
              Text(l10n.bleeding),
              const SizedBox(height: 4),
              SegmentedButton<Bleeding>(
                segments: [
                  ButtonSegment(
                    value: Bleeding.none,
                    label: Text(l10n.bleedingNone),
                  ),
                  ButtonSegment(
                    value: Bleeding.period,
                    label: Text(l10n.bleedingPeriod),
                  ),
                  ButtonSegment(
                    value: Bleeding.spotting,
                    label: Text(l10n.bleedingSpotting),
                  ),
                ],
                selected: {_bleeding},
                onSelectionChanged: (selection) =>
                    setState(() => _bleeding = selection.first),
              ),
              const SizedBox(height: 12),
              // --- exclusion flags (compact) ---------------------------
              // Always visible: interruptions (illness, alcohol, travel,
              // other) apply to temperature interruptions regardless of
              // bleeding. Excluded (interrupted) days never start a cycle.
              Text(l10n.excludesCaption,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(l10n.excludeIllness),
                    selected: _excludeIllness,
                    onSelected: (v) => setState(() => _excludeIllness = v),
                  ),
                  FilterChip(
                    label: Text(l10n.excludeAlcohol),
                    selected: _excludeAlcohol,
                    onSelected: (v) => setState(() => _excludeAlcohol = v),
                  ),
                  FilterChip(
                    label: Text(l10n.excludeTravel),
                    selected: _excludeTravel,
                    onSelected: (v) => setState(() => _excludeTravel = v),
                  ),
                  FilterChip(
                    label: Text(l10n.excludeOther),
                    selected: _excludeOther,
                    onSelected: (v) => setState(() => _excludeOther = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // --- mucus: feeling -> auto NFP value, override allowed ---
              DropdownButtonFormField<MucusFeeling?>(
                initialValue: _feeling,
                decoration: InputDecoration(labelText: l10n.mucusFeeling),
                items: [
                  DropdownMenuItem<MucusFeeling?>(
                    value: null,
                    child: Text(l10n.mucusFeelingUnset),
                  ),
                  ...MucusFeeling.values.map(
                    (f) => DropdownMenuItem<MucusFeeling?>(
                      value: f,
                      child: Text(
                        '${_feelingLabel(f, l10n)} → NFP ${f.mappedNfp}',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _feeling = value;
                  // Auto-mapping: picking a feeling pre-selects the mapped
                  // NFP value. The user can override it afterwards using
                  // the segmented row below (pure assistant, no evaluation).
                  if (value != null) _mucusNfp = value.mappedNfp;
                }),
              ),
              const SizedBox(height: 8),
              Text(l10n.mucusNfpValue),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                segments: [
                  for (var n = 0; n <= 4; n++)
                    ButtonSegment(value: n, label: Text('$n')),
                ],
                selected: _mucusNfp != null ? {_mucusNfp!} : <int>{},
                emptySelectionAllowed: true,
                onSelectionChanged: (selection) => setState(() {
                  _mucusNfp = selection.isEmpty ? null : selection.first;
                }),
              ),
              ExpansionTile(
                title: Text(l10n.mucusMappingTitle,
                    style: Theme.of(context).textTheme.bodyMedium),
                children: [
                  ...MucusFeeling.values.map(
                    (f) => ListTile(
                      dense: true,
                      title: Text(_feelingLabel(f, l10n)),
                      trailing: Text(
                        'NFP ${f.mappedNfp}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      l10n.mucusMappingNote,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // --- cervix (optional) -----------------------------------
              TextFormField(
                controller: _cervixController,
                decoration: InputDecoration(labelText: l10n.cervix),
              ),
              const SizedBox(height: 12),
              // --- toggles ----------------------------------------------
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(l10n.pain),
                    selected: _pain,
                    onSelected: (v) => setState(() => _pain = v),
                  ),
                  FilterChip(
                    label: Text(l10n.mood),
                    selected: _mood,
                    onSelected: (v) => setState(() => _mood = v),
                  ),
                  FilterChip(
                    label: Text(l10n.desire),
                    selected: _desire,
                    onSelected: (v) => setState(() => _desire = v),
                  ),
                  FilterChip(
                    label: Text(l10n.sex),
                    selected: _sex,
                    onSelected: (v) => setState(() => _sex = v),
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
  ) {
    return entriesAsync.when(
      loading: () => <Widget>[const SizedBox.shrink()],
      error: (e, s) => <Widget>[Text(l10n.loadFailed)],
      data: (entries) {
        if (entries.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(l10n.noEntriesYet,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ];
        }
        final cycles = groupIntoCycles(entries);
        return [
          for (var i = cycles.length - 1; i >= 0; i--)
            _cycleTile(l10n, cycles[i]),
        ];
      },
    );
  }

  Widget _cycleTile(AppLocalizations l10n, Cycle cycle) {
    final locale = Localizations.localeOf(context).toString();
    final startLabel = _formatDay(cycle.startDate, locale);
    final endLabel = _formatDay(cycle.endDate, locale);
    final title = cycle.startsAtMenstruation
        ? l10n.cycleGroupOnset(startLabel)
        // Leading group predates the first known period onset: title shows
        // the range END, since the begin is unknown.
        : l10n.cycleGroupLeading(endLabel);
    final dayCount = DateOnly.daysBetween(cycle.endDate, cycle.startDate) + 1;

    return ExpansionTile(
      // Most recent work stays at the top of the list.
      title: Text(title),
      subtitle: Text(l10n.cycleDays(dayCount)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.cycleTapToEdit,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final day in cycle.days.reversed) _dayTile(day),
      ],
    );
  }

  Widget _dayTile(DailyEntry day) {
    final locale = Localizations.localeOf(context).toString();
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _bleedingMarker(day),
      title: Text(_formatDay(day.date, locale)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (day.bbtC != null)
            Text(
              '${_formatBbt(day.bbtC!, locale)} °C',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (day.mucusNfp != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('NFP ${day.mucusNfp}',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          ],
        ],
      ),
      subtitle: day.notes != null
          ? Text(
              day.notes!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: () {
        ref.read(selectedDateProvider.notifier).state =
            DateOnly.normalize(day.date);
      },
    );
  }

  Widget _bleedingMarker(DailyEntry day) {
    final color = switch (day.bleeding) {
      Bleeding.none => Theme.of(context).colorScheme.outlineVariant,
      Bleeding.period => Theme.of(context).colorScheme.error,
      Bleeding.spotting =>
        Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        if (day.isExcluded)
          Positioned(
            right: -6,
            top: -6,
            child: Icon(Icons.warning_amber,
                size: 14, color: Theme.of(context).colorScheme.secondary),
          ),
      ],
    );
  }
}
