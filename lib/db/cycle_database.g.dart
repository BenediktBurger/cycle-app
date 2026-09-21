// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_database.dart';

// ignore_for_file: type=lint
class $CycleEntriesTable extends CycleEntries
    with TableInfo<$CycleEntriesTable, CycleEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CycleEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> date =
      GeneratedColumn<int>('date', aliasedName, false,
              type: DriftSqlType.int, requiredDuringInsert: true)
          .withConverter<DateTime>($CycleEntriesTable.$converterdate);
  static const VerificationMeta _tempDisturbancesMeta =
      const VerificationMeta('tempDisturbances');
  @override
  late final GeneratedColumn<int> tempDisturbances = GeneratedColumn<int>(
      'temp_disturbances', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints:
          'NOT NULL DEFAULT 0 CHECK (temp_disturbances BETWEEN 0 AND 15)',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _bbtCMeta = const VerificationMeta('bbtC');
  @override
  late final GeneratedColumn<double> bbtC = GeneratedColumn<double>(
      'bbt_c', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _measuredAtMinutesMeta =
      const VerificationMeta('measuredAtMinutes');
  @override
  late final GeneratedColumn<int> measuredAtMinutes = GeneratedColumn<int>(
      'measured_at_minutes', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints:
          'CHECK (measured_at_minutes IS NULL OR (measured_at_minutes BETWEEN 0 AND 1439))');
  @override
  late final GeneratedColumnWithTypeConverter<Bleeding, int> bleeding =
      GeneratedColumn<int>('bleeding', aliasedName, false,
              type: DriftSqlType.int,
              requiredDuringInsert: false,
              defaultValue: const Constant(0))
          .withConverter<Bleeding>($CycleEntriesTable.$converterbleeding);
  static const VerificationMeta _mucusSignMeta =
      const VerificationMeta('mucusSign');
  @override
  late final GeneratedColumn<String> mucusSign = GeneratedColumn<String>(
      'mucus_sign', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints:
          'CHECK (mucus_sign IS NULL OR mucus_sign IN (\'t\', \'nothing\', \'f\', \'s\', \'fs\', \'a\'))');
  static const VerificationMeta _mucusQualityMeta =
      const VerificationMeta('mucusQuality');
  @override
  late final GeneratedColumn<String> mucusQuality = GeneratedColumn<String>(
      'mucus_quality', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints:
          'CHECK (mucus_quality IS NULL OR (mucus_sign = \'s\' AND mucus_quality IN (\'w\', \'mi\', \'cr\', \'kl\', \'glb\', \'g\', \'ew\', \'gl\', \'fl\', \'ns\')))');
  static const VerificationMeta _cervixPositionMeta =
      const VerificationMeta('cervixPosition');
  @override
  late final GeneratedColumn<String> cervixPosition = GeneratedColumn<String>(
      'cervix_position', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints:
          'CHECK (cervix_position IS NULL OR cervix_position IN (\'low\', \'medium\', \'high\', \'veryHigh\', \'unreachable\'))');
  static const VerificationMeta _cervixOpeningMeta =
      const VerificationMeta('cervixOpening');
  @override
  late final GeneratedColumn<String> cervixOpening = GeneratedColumn<String>(
      'cervix_opening', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints:
          'CHECK (cervix_opening IS NULL OR cervix_opening IN (\'closed\', \'middle\', \'open\'))');
  static const VerificationMeta _cervixFirmnessMeta =
      const VerificationMeta('cervixFirmness');
  @override
  late final GeneratedColumn<String> cervixFirmness = GeneratedColumn<String>(
      'cervix_firmness', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints:
          'CHECK (cervix_firmness IS NULL OR cervix_firmness IN (\'hard\', \'halfSoft\', \'soft\'))');
  static const VerificationMeta _painBreastMeta =
      const VerificationMeta('painBreast');
  @override
  late final GeneratedColumn<bool> painBreast = GeneratedColumn<bool>(
      'pain_breast', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("pain_breast" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _painMittelschmerzMeta =
      const VerificationMeta('painMittelschmerz');
  @override
  late final GeneratedColumn<bool> painMittelschmerz = GeneratedColumn<bool>(
      'pain_mittelschmerz', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("pain_mittelschmerz" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _sexTimingsMeta =
      const VerificationMeta('sexTimings');
  @override
  late final GeneratedColumn<int> sexTimings = GeneratedColumn<int>(
      'sex_timings', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints:
          'NOT NULL DEFAULT 0 CHECK (sex_timings BETWEEN 0 AND 7)',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        date,
        tempDisturbances,
        bbtC,
        measuredAtMinutes,
        bleeding,
        mucusSign,
        mucusQuality,
        cervixPosition,
        cervixOpening,
        cervixFirmness,
        painBreast,
        painMittelschmerz,
        sexTimings,
        notes,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cycle_entries';
  @override
  VerificationContext validateIntegrity(Insertable<CycleEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('temp_disturbances')) {
      context.handle(
          _tempDisturbancesMeta,
          tempDisturbances.isAcceptableOrUnknown(
              data['temp_disturbances']!, _tempDisturbancesMeta));
    }
    if (data.containsKey('bbt_c')) {
      context.handle(
          _bbtCMeta, bbtC.isAcceptableOrUnknown(data['bbt_c']!, _bbtCMeta));
    }
    if (data.containsKey('measured_at_minutes')) {
      context.handle(
          _measuredAtMinutesMeta,
          measuredAtMinutes.isAcceptableOrUnknown(
              data['measured_at_minutes']!, _measuredAtMinutesMeta));
    }
    if (data.containsKey('mucus_sign')) {
      context.handle(_mucusSignMeta,
          mucusSign.isAcceptableOrUnknown(data['mucus_sign']!, _mucusSignMeta));
    }
    if (data.containsKey('mucus_quality')) {
      context.handle(
          _mucusQualityMeta,
          mucusQuality.isAcceptableOrUnknown(
              data['mucus_quality']!, _mucusQualityMeta));
    }
    if (data.containsKey('cervix_position')) {
      context.handle(
          _cervixPositionMeta,
          cervixPosition.isAcceptableOrUnknown(
              data['cervix_position']!, _cervixPositionMeta));
    }
    if (data.containsKey('cervix_opening')) {
      context.handle(
          _cervixOpeningMeta,
          cervixOpening.isAcceptableOrUnknown(
              data['cervix_opening']!, _cervixOpeningMeta));
    }
    if (data.containsKey('cervix_firmness')) {
      context.handle(
          _cervixFirmnessMeta,
          cervixFirmness.isAcceptableOrUnknown(
              data['cervix_firmness']!, _cervixFirmnessMeta));
    }
    if (data.containsKey('pain_breast')) {
      context.handle(
          _painBreastMeta,
          painBreast.isAcceptableOrUnknown(
              data['pain_breast']!, _painBreastMeta));
    }
    if (data.containsKey('pain_mittelschmerz')) {
      context.handle(
          _painMittelschmerzMeta,
          painMittelschmerz.isAcceptableOrUnknown(
              data['pain_mittelschmerz']!, _painMittelschmerzMeta));
    }
    if (data.containsKey('sex_timings')) {
      context.handle(
          _sexTimingsMeta,
          sexTimings.isAcceptableOrUnknown(
              data['sex_timings']!, _sexTimingsMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CycleEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CycleEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      date: $CycleEntriesTable.$converterdate.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}date'])!),
      tempDisturbances: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}temp_disturbances'])!,
      bbtC: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}bbt_c']),
      measuredAtMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}measured_at_minutes']),
      bleeding: $CycleEntriesTable.$converterbleeding.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bleeding'])!),
      mucusSign: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mucus_sign']),
      mucusQuality: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mucus_quality']),
      cervixPosition: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cervix_position']),
      cervixOpening: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cervix_opening']),
      cervixFirmness: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cervix_firmness']),
      painBreast: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}pain_breast'])!,
      painMittelschmerz: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}pain_mittelschmerz'])!,
      sexTimings: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sex_timings'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CycleEntriesTable createAlias(String alias) {
    return $CycleEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterdate =
      const EpochDayConverter();
  static TypeConverter<Bleeding, int> $converterbleeding =
      const BleedingLevelConverter();
}

class CycleEntry extends DataClass implements Insertable<CycleEntry> {
  final int id;

  /// Calendar day, stored as unix-epoch days (see EpochDayConverter).
  final DateTime date;

  /// Raw temperature-disturbance flags of the day (the NER "Störungen"
  /// vocabulary): one INTEGER mask, the OR of the [TempDisturbance] bits —
  /// sp(1) late to bed, a(2) frequent night awakening, alk(4) alcohol,
  /// kr(8) illness. 0 = no disturbance. Reise (travel) is deliberately NOT
  /// representable. This is RAW data whose remaining visual consumer is
  /// the Tagebuch list's interrupted-day badge (the temperature curve is
  /// MARK-keyed since owner decision 2026-09-19 — the ignoreTemperature
  /// mark dims the curve, never this mask); the temperature evaluation
  /// uses the
  /// separate ignoreTemperature MARK (user_marks).
  /// customConstraint replaces drift's own constraints, so NOT NULL, the
  /// default 0 and the 0..15 range check are written out explicitly inside
  /// the constraint string (a bare CHECK would silently drop both). The
  /// engine-level CHECK mirrors the domain constructor assert so foreign
  /// data cannot write an impossible mask.
  final int tempDisturbances;

  /// Basal body temperature in degrees Celsius, when measured.
  final double? bbtC;

  /// Time-of-day of the temperature measurement, minutes since midnight
  /// (0–1439), NULL when not recorded. Engine-level CHECK mirrors the
  /// shared parse helper (lib/domain/models.dart) so foreign data (e.g. a
  /// future import path) cannot write an impossible time.
  final int? measuredAtMinutes;

  /// Bleeding intensity on the shared 6-step numeric scale, stored as the
  /// INTEGER [Bleeding.level]: none(0) / spotting(1) / light(2) / medium(3) /
  /// heavy(4) / maximum(5). The converter derives every mapping from
  /// [Bleeding.level],
  /// never from the declaration index; an unknown stored number throws so
  /// corrupt data is surfaced instead of silently mapped. The default 0
  /// stores an explicit `none` (a day with no observation still has a value).
  final Bleeding bleeding;

  /// Fertility sign recorded on the day: NULL when no observation, else one
  /// of the stable tokens 't' / 'nothing' / 'f' / 's' / 'fs' / 'a' (the
  /// MucusSign enum names — TEXT, unlike bleeding's numeric column; never
  /// display glyphs; 'fs' is "f vor S an einem Tag", a sign of its own with
  /// NO quality qualifier). customConstraint replaces drift's own
  /// constraints, which is fine here: SQLite columns admit NULL unless NOT
  /// NULL is written, and the check below allows exactly NULL or the
  /// vocabulary.
  final String? mucusSign;

  /// Quality qualifier of the mucus sign S; NULL for every sign other than
  /// 's' and for days without a sign ('fs' deliberately carries no
  /// quality — it is not the S sign). Enforced at the engine level so
  /// broken data (e.g. from a future import path) cannot be written.
  final String? mucusQuality;

  /// Muttermund (cervix) POSITION of the day, as a nullable TEXT token from
  /// the [CervixPosition] enum-name vocabulary: NULL when not observed,
  /// else 'low' / 'medium' / 'high' / 'veryHigh' / 'unreachable' (tief …
  /// unerreichbar). Stored like mucus_sign (TEXT enum-name tokens, engine
  /// CHECK on the vocabulary; note the deliberate distinction
  /// position:'medium' — the OPENING column below spells its middle value
  /// 'middle'). German display labels live in the l10n arbs.
  final String? cervixPosition;

  /// Muttermund (cervix) OPENING of the day, as above: NULL when not
  /// observed, else 'closed' / 'middle' / 'open' (geschlossen · mittel ·
  /// offen). Independent of cervix_position.
  final String? cervixOpening;

  /// Muttermund (cervix) FIRMNESS of the day, as above: NULL when not
  /// observed, else 'hard' / 'halfSoft' / 'soft' (paper shorthand h / h/w /
  /// w — fest / teils fest, teils weich / weich). Stored like mucus_sign
  /// (TEXT enum-name tokens, engine CHECK on the vocabulary; the tokens
  /// never collide with a position or opening token). German display labels
  /// live in the l10n arbs.
  final String? cervixFirmness;

  /// Pain options of the day, as two independent flags with the cheat
  /// sheet's letters: breast tenderness (painBreast, letter B) and
  /// ovulation pain / Mittelschmerz (painMittelschmerz, letter M). Modeled
  /// like the disturbance flags: plain booleans, no interval system.
  final bool painBreast;
  final bool painMittelschmerz;

  /// Times of day sex happened, as an INTEGER bitmask of [SexTiming.bit]:
  /// start(1) / middle(2) / end(4), OR-combined — multiple bits mean
  /// multiple times on the same day; 0 = not recorded. "Sex happened, time
  /// unknown" is deliberately NOT representable (the observation is only
  /// recorded together with a concrete time slot). customConstraint replaces
  /// drift's own constraints, so NOT NULL and the column default 0 are
  /// written out explicitly inside the constraint string (a bare CHECK
  /// would silently drop both, leaving the column nullable).
  final int sexTimings;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CycleEntry(
      {required this.id,
      required this.date,
      required this.tempDisturbances,
      this.bbtC,
      this.measuredAtMinutes,
      required this.bleeding,
      this.mucusSign,
      this.mucusQuality,
      this.cervixPosition,
      this.cervixOpening,
      this.cervixFirmness,
      required this.painBreast,
      required this.painMittelschmerz,
      required this.sexTimings,
      this.notes,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['date'] =
          Variable<int>($CycleEntriesTable.$converterdate.toSql(date));
    }
    map['temp_disturbances'] = Variable<int>(tempDisturbances);
    if (!nullToAbsent || bbtC != null) {
      map['bbt_c'] = Variable<double>(bbtC);
    }
    if (!nullToAbsent || measuredAtMinutes != null) {
      map['measured_at_minutes'] = Variable<int>(measuredAtMinutes);
    }
    {
      map['bleeding'] =
          Variable<int>($CycleEntriesTable.$converterbleeding.toSql(bleeding));
    }
    if (!nullToAbsent || mucusSign != null) {
      map['mucus_sign'] = Variable<String>(mucusSign);
    }
    if (!nullToAbsent || mucusQuality != null) {
      map['mucus_quality'] = Variable<String>(mucusQuality);
    }
    if (!nullToAbsent || cervixPosition != null) {
      map['cervix_position'] = Variable<String>(cervixPosition);
    }
    if (!nullToAbsent || cervixOpening != null) {
      map['cervix_opening'] = Variable<String>(cervixOpening);
    }
    if (!nullToAbsent || cervixFirmness != null) {
      map['cervix_firmness'] = Variable<String>(cervixFirmness);
    }
    map['pain_breast'] = Variable<bool>(painBreast);
    map['pain_mittelschmerz'] = Variable<bool>(painMittelschmerz);
    map['sex_timings'] = Variable<int>(sexTimings);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CycleEntriesCompanion toCompanion(bool nullToAbsent) {
    return CycleEntriesCompanion(
      id: Value(id),
      date: Value(date),
      tempDisturbances: Value(tempDisturbances),
      bbtC: bbtC == null && nullToAbsent ? const Value.absent() : Value(bbtC),
      measuredAtMinutes: measuredAtMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(measuredAtMinutes),
      bleeding: Value(bleeding),
      mucusSign: mucusSign == null && nullToAbsent
          ? const Value.absent()
          : Value(mucusSign),
      mucusQuality: mucusQuality == null && nullToAbsent
          ? const Value.absent()
          : Value(mucusQuality),
      cervixPosition: cervixPosition == null && nullToAbsent
          ? const Value.absent()
          : Value(cervixPosition),
      cervixOpening: cervixOpening == null && nullToAbsent
          ? const Value.absent()
          : Value(cervixOpening),
      cervixFirmness: cervixFirmness == null && nullToAbsent
          ? const Value.absent()
          : Value(cervixFirmness),
      painBreast: Value(painBreast),
      painMittelschmerz: Value(painMittelschmerz),
      sexTimings: Value(sexTimings),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CycleEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CycleEntry(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      tempDisturbances: serializer.fromJson<int>(json['tempDisturbances']),
      bbtC: serializer.fromJson<double?>(json['bbtC']),
      measuredAtMinutes: serializer.fromJson<int?>(json['measuredAtMinutes']),
      bleeding: serializer.fromJson<Bleeding>(json['bleeding']),
      mucusSign: serializer.fromJson<String?>(json['mucusSign']),
      mucusQuality: serializer.fromJson<String?>(json['mucusQuality']),
      cervixPosition: serializer.fromJson<String?>(json['cervixPosition']),
      cervixOpening: serializer.fromJson<String?>(json['cervixOpening']),
      cervixFirmness: serializer.fromJson<String?>(json['cervixFirmness']),
      painBreast: serializer.fromJson<bool>(json['painBreast']),
      painMittelschmerz: serializer.fromJson<bool>(json['painMittelschmerz']),
      sexTimings: serializer.fromJson<int>(json['sexTimings']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<DateTime>(date),
      'tempDisturbances': serializer.toJson<int>(tempDisturbances),
      'bbtC': serializer.toJson<double?>(bbtC),
      'measuredAtMinutes': serializer.toJson<int?>(measuredAtMinutes),
      'bleeding': serializer.toJson<Bleeding>(bleeding),
      'mucusSign': serializer.toJson<String?>(mucusSign),
      'mucusQuality': serializer.toJson<String?>(mucusQuality),
      'cervixPosition': serializer.toJson<String?>(cervixPosition),
      'cervixOpening': serializer.toJson<String?>(cervixOpening),
      'cervixFirmness': serializer.toJson<String?>(cervixFirmness),
      'painBreast': serializer.toJson<bool>(painBreast),
      'painMittelschmerz': serializer.toJson<bool>(painMittelschmerz),
      'sexTimings': serializer.toJson<int>(sexTimings),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CycleEntry copyWith(
          {int? id,
          DateTime? date,
          int? tempDisturbances,
          Value<double?> bbtC = const Value.absent(),
          Value<int?> measuredAtMinutes = const Value.absent(),
          Bleeding? bleeding,
          Value<String?> mucusSign = const Value.absent(),
          Value<String?> mucusQuality = const Value.absent(),
          Value<String?> cervixPosition = const Value.absent(),
          Value<String?> cervixOpening = const Value.absent(),
          Value<String?> cervixFirmness = const Value.absent(),
          bool? painBreast,
          bool? painMittelschmerz,
          int? sexTimings,
          Value<String?> notes = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      CycleEntry(
        id: id ?? this.id,
        date: date ?? this.date,
        tempDisturbances: tempDisturbances ?? this.tempDisturbances,
        bbtC: bbtC.present ? bbtC.value : this.bbtC,
        measuredAtMinutes: measuredAtMinutes.present
            ? measuredAtMinutes.value
            : this.measuredAtMinutes,
        bleeding: bleeding ?? this.bleeding,
        mucusSign: mucusSign.present ? mucusSign.value : this.mucusSign,
        mucusQuality:
            mucusQuality.present ? mucusQuality.value : this.mucusQuality,
        cervixPosition:
            cervixPosition.present ? cervixPosition.value : this.cervixPosition,
        cervixOpening:
            cervixOpening.present ? cervixOpening.value : this.cervixOpening,
        cervixFirmness:
            cervixFirmness.present ? cervixFirmness.value : this.cervixFirmness,
        painBreast: painBreast ?? this.painBreast,
        painMittelschmerz: painMittelschmerz ?? this.painMittelschmerz,
        sexTimings: sexTimings ?? this.sexTimings,
        notes: notes.present ? notes.value : this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CycleEntry copyWithCompanion(CycleEntriesCompanion data) {
    return CycleEntry(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      tempDisturbances: data.tempDisturbances.present
          ? data.tempDisturbances.value
          : this.tempDisturbances,
      bbtC: data.bbtC.present ? data.bbtC.value : this.bbtC,
      measuredAtMinutes: data.measuredAtMinutes.present
          ? data.measuredAtMinutes.value
          : this.measuredAtMinutes,
      bleeding: data.bleeding.present ? data.bleeding.value : this.bleeding,
      mucusSign: data.mucusSign.present ? data.mucusSign.value : this.mucusSign,
      mucusQuality: data.mucusQuality.present
          ? data.mucusQuality.value
          : this.mucusQuality,
      cervixPosition: data.cervixPosition.present
          ? data.cervixPosition.value
          : this.cervixPosition,
      cervixOpening: data.cervixOpening.present
          ? data.cervixOpening.value
          : this.cervixOpening,
      cervixFirmness: data.cervixFirmness.present
          ? data.cervixFirmness.value
          : this.cervixFirmness,
      painBreast:
          data.painBreast.present ? data.painBreast.value : this.painBreast,
      painMittelschmerz: data.painMittelschmerz.present
          ? data.painMittelschmerz.value
          : this.painMittelschmerz,
      sexTimings:
          data.sexTimings.present ? data.sexTimings.value : this.sexTimings,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CycleEntry(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('tempDisturbances: $tempDisturbances, ')
          ..write('bbtC: $bbtC, ')
          ..write('measuredAtMinutes: $measuredAtMinutes, ')
          ..write('bleeding: $bleeding, ')
          ..write('mucusSign: $mucusSign, ')
          ..write('mucusQuality: $mucusQuality, ')
          ..write('cervixPosition: $cervixPosition, ')
          ..write('cervixOpening: $cervixOpening, ')
          ..write('cervixFirmness: $cervixFirmness, ')
          ..write('painBreast: $painBreast, ')
          ..write('painMittelschmerz: $painMittelschmerz, ')
          ..write('sexTimings: $sexTimings, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      date,
      tempDisturbances,
      bbtC,
      measuredAtMinutes,
      bleeding,
      mucusSign,
      mucusQuality,
      cervixPosition,
      cervixOpening,
      cervixFirmness,
      painBreast,
      painMittelschmerz,
      sexTimings,
      notes,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CycleEntry &&
          other.id == this.id &&
          other.date == this.date &&
          other.tempDisturbances == this.tempDisturbances &&
          other.bbtC == this.bbtC &&
          other.measuredAtMinutes == this.measuredAtMinutes &&
          other.bleeding == this.bleeding &&
          other.mucusSign == this.mucusSign &&
          other.mucusQuality == this.mucusQuality &&
          other.cervixPosition == this.cervixPosition &&
          other.cervixOpening == this.cervixOpening &&
          other.cervixFirmness == this.cervixFirmness &&
          other.painBreast == this.painBreast &&
          other.painMittelschmerz == this.painMittelschmerz &&
          other.sexTimings == this.sexTimings &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CycleEntriesCompanion extends UpdateCompanion<CycleEntry> {
  final Value<int> id;
  final Value<DateTime> date;
  final Value<int> tempDisturbances;
  final Value<double?> bbtC;
  final Value<int?> measuredAtMinutes;
  final Value<Bleeding> bleeding;
  final Value<String?> mucusSign;
  final Value<String?> mucusQuality;
  final Value<String?> cervixPosition;
  final Value<String?> cervixOpening;
  final Value<String?> cervixFirmness;
  final Value<bool> painBreast;
  final Value<bool> painMittelschmerz;
  final Value<int> sexTimings;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const CycleEntriesCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.tempDisturbances = const Value.absent(),
    this.bbtC = const Value.absent(),
    this.measuredAtMinutes = const Value.absent(),
    this.bleeding = const Value.absent(),
    this.mucusSign = const Value.absent(),
    this.mucusQuality = const Value.absent(),
    this.cervixPosition = const Value.absent(),
    this.cervixOpening = const Value.absent(),
    this.cervixFirmness = const Value.absent(),
    this.painBreast = const Value.absent(),
    this.painMittelschmerz = const Value.absent(),
    this.sexTimings = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CycleEntriesCompanion.insert({
    this.id = const Value.absent(),
    required DateTime date,
    this.tempDisturbances = const Value.absent(),
    this.bbtC = const Value.absent(),
    this.measuredAtMinutes = const Value.absent(),
    this.bleeding = const Value.absent(),
    this.mucusSign = const Value.absent(),
    this.mucusQuality = const Value.absent(),
    this.cervixPosition = const Value.absent(),
    this.cervixOpening = const Value.absent(),
    this.cervixFirmness = const Value.absent(),
    this.painBreast = const Value.absent(),
    this.painMittelschmerz = const Value.absent(),
    this.sexTimings = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : date = Value(date);
  static Insertable<CycleEntry> custom({
    Expression<int>? id,
    Expression<int>? date,
    Expression<int>? tempDisturbances,
    Expression<double>? bbtC,
    Expression<int>? measuredAtMinutes,
    Expression<int>? bleeding,
    Expression<String>? mucusSign,
    Expression<String>? mucusQuality,
    Expression<String>? cervixPosition,
    Expression<String>? cervixOpening,
    Expression<String>? cervixFirmness,
    Expression<bool>? painBreast,
    Expression<bool>? painMittelschmerz,
    Expression<int>? sexTimings,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (tempDisturbances != null) 'temp_disturbances': tempDisturbances,
      if (bbtC != null) 'bbt_c': bbtC,
      if (measuredAtMinutes != null) 'measured_at_minutes': measuredAtMinutes,
      if (bleeding != null) 'bleeding': bleeding,
      if (mucusSign != null) 'mucus_sign': mucusSign,
      if (mucusQuality != null) 'mucus_quality': mucusQuality,
      if (cervixPosition != null) 'cervix_position': cervixPosition,
      if (cervixOpening != null) 'cervix_opening': cervixOpening,
      if (cervixFirmness != null) 'cervix_firmness': cervixFirmness,
      if (painBreast != null) 'pain_breast': painBreast,
      if (painMittelschmerz != null) 'pain_mittelschmerz': painMittelschmerz,
      if (sexTimings != null) 'sex_timings': sexTimings,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CycleEntriesCompanion copyWith(
      {Value<int>? id,
      Value<DateTime>? date,
      Value<int>? tempDisturbances,
      Value<double?>? bbtC,
      Value<int?>? measuredAtMinutes,
      Value<Bleeding>? bleeding,
      Value<String?>? mucusSign,
      Value<String?>? mucusQuality,
      Value<String?>? cervixPosition,
      Value<String?>? cervixOpening,
      Value<String?>? cervixFirmness,
      Value<bool>? painBreast,
      Value<bool>? painMittelschmerz,
      Value<int>? sexTimings,
      Value<String?>? notes,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return CycleEntriesCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      tempDisturbances: tempDisturbances ?? this.tempDisturbances,
      bbtC: bbtC ?? this.bbtC,
      measuredAtMinutes: measuredAtMinutes ?? this.measuredAtMinutes,
      bleeding: bleeding ?? this.bleeding,
      mucusSign: mucusSign ?? this.mucusSign,
      mucusQuality: mucusQuality ?? this.mucusQuality,
      cervixPosition: cervixPosition ?? this.cervixPosition,
      cervixOpening: cervixOpening ?? this.cervixOpening,
      cervixFirmness: cervixFirmness ?? this.cervixFirmness,
      painBreast: painBreast ?? this.painBreast,
      painMittelschmerz: painMittelschmerz ?? this.painMittelschmerz,
      sexTimings: sexTimings ?? this.sexTimings,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] =
          Variable<int>($CycleEntriesTable.$converterdate.toSql(date.value));
    }
    if (tempDisturbances.present) {
      map['temp_disturbances'] = Variable<int>(tempDisturbances.value);
    }
    if (bbtC.present) {
      map['bbt_c'] = Variable<double>(bbtC.value);
    }
    if (measuredAtMinutes.present) {
      map['measured_at_minutes'] = Variable<int>(measuredAtMinutes.value);
    }
    if (bleeding.present) {
      map['bleeding'] = Variable<int>(
          $CycleEntriesTable.$converterbleeding.toSql(bleeding.value));
    }
    if (mucusSign.present) {
      map['mucus_sign'] = Variable<String>(mucusSign.value);
    }
    if (mucusQuality.present) {
      map['mucus_quality'] = Variable<String>(mucusQuality.value);
    }
    if (cervixPosition.present) {
      map['cervix_position'] = Variable<String>(cervixPosition.value);
    }
    if (cervixOpening.present) {
      map['cervix_opening'] = Variable<String>(cervixOpening.value);
    }
    if (cervixFirmness.present) {
      map['cervix_firmness'] = Variable<String>(cervixFirmness.value);
    }
    if (painBreast.present) {
      map['pain_breast'] = Variable<bool>(painBreast.value);
    }
    if (painMittelschmerz.present) {
      map['pain_mittelschmerz'] = Variable<bool>(painMittelschmerz.value);
    }
    if (sexTimings.present) {
      map['sex_timings'] = Variable<int>(sexTimings.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CycleEntriesCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('tempDisturbances: $tempDisturbances, ')
          ..write('bbtC: $bbtC, ')
          ..write('measuredAtMinutes: $measuredAtMinutes, ')
          ..write('bleeding: $bleeding, ')
          ..write('mucusSign: $mucusSign, ')
          ..write('mucusQuality: $mucusQuality, ')
          ..write('cervixPosition: $cervixPosition, ')
          ..write('cervixOpening: $cervixOpening, ')
          ..write('cervixFirmness: $cervixFirmness, ')
          ..write('painBreast: $painBreast, ')
          ..write('painMittelschmerz: $painMittelschmerz, ')
          ..write('sexTimings: $sexTimings, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $UserMarksTable extends UserMarks
    with TableInfo<$UserMarksTable, UserMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserMarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> entryDate =
      GeneratedColumn<int>('entry_date', aliasedName, false,
              type: DriftSqlType.int, requiredDuringInsert: true)
          .withConverter<DateTime>($UserMarksTable.$converterentryDate);
  static const VerificationMeta _markTypeMeta =
      const VerificationMeta('markType');
  @override
  late final GeneratedColumn<String> markType = GeneratedColumn<String>(
      'mark_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('user'));
  @override
  List<GeneratedColumn> get $columns => [id, entryDate, markType, author];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_marks';
  @override
  VerificationContext validateIntegrity(Insertable<UserMark> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('mark_type')) {
      context.handle(_markTypeMeta,
          markType.isAcceptableOrUnknown(data['mark_type']!, _markTypeMeta));
    } else if (isInserting) {
      context.missing(_markTypeMeta);
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserMark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserMark(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      entryDate: $UserMarksTable.$converterentryDate.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}entry_date'])!),
      markType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mark_type'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author'])!,
    );
  }

  @override
  $UserMarksTable createAlias(String alias) {
    return $UserMarksTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterentryDate =
      const EpochDayConverter();
}

class UserMark extends DataClass implements Insertable<UserMark> {
  final int id;

  /// Calendar day the mark belongs to (unix-epoch days).
  final DateTime entryDate;

  /// Marking tool identifier, e.g. one of the [MarkTypes] constants.
  final String markType;

  /// Who placed the mark. 'user' today; foreign imports (drip CSV, old
  /// export documents) derive marks with the 'import' author; open TEXT in
  /// storage for future authoring modes instead of constraining to an enum.
  final String author;
  const UserMark(
      {required this.id,
      required this.entryDate,
      required this.markType,
      required this.author});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['entry_date'] =
          Variable<int>($UserMarksTable.$converterentryDate.toSql(entryDate));
    }
    map['mark_type'] = Variable<String>(markType);
    map['author'] = Variable<String>(author);
    return map;
  }

  UserMarksCompanion toCompanion(bool nullToAbsent) {
    return UserMarksCompanion(
      id: Value(id),
      entryDate: Value(entryDate),
      markType: Value(markType),
      author: Value(author),
    );
  }

  factory UserMark.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserMark(
      id: serializer.fromJson<int>(json['id']),
      entryDate: serializer.fromJson<DateTime>(json['entryDate']),
      markType: serializer.fromJson<String>(json['markType']),
      author: serializer.fromJson<String>(json['author']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entryDate': serializer.toJson<DateTime>(entryDate),
      'markType': serializer.toJson<String>(markType),
      'author': serializer.toJson<String>(author),
    };
  }

  UserMark copyWith(
          {int? id, DateTime? entryDate, String? markType, String? author}) =>
      UserMark(
        id: id ?? this.id,
        entryDate: entryDate ?? this.entryDate,
        markType: markType ?? this.markType,
        author: author ?? this.author,
      );
  UserMark copyWithCompanion(UserMarksCompanion data) {
    return UserMark(
      id: data.id.present ? data.id.value : this.id,
      entryDate: data.entryDate.present ? data.entryDate.value : this.entryDate,
      markType: data.markType.present ? data.markType.value : this.markType,
      author: data.author.present ? data.author.value : this.author,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserMark(')
          ..write('id: $id, ')
          ..write('entryDate: $entryDate, ')
          ..write('markType: $markType, ')
          ..write('author: $author')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, entryDate, markType, author);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserMark &&
          other.id == this.id &&
          other.entryDate == this.entryDate &&
          other.markType == this.markType &&
          other.author == this.author);
}

class UserMarksCompanion extends UpdateCompanion<UserMark> {
  final Value<int> id;
  final Value<DateTime> entryDate;
  final Value<String> markType;
  final Value<String> author;
  const UserMarksCompanion({
    this.id = const Value.absent(),
    this.entryDate = const Value.absent(),
    this.markType = const Value.absent(),
    this.author = const Value.absent(),
  });
  UserMarksCompanion.insert({
    this.id = const Value.absent(),
    required DateTime entryDate,
    required String markType,
    this.author = const Value.absent(),
  })  : entryDate = Value(entryDate),
        markType = Value(markType);
  static Insertable<UserMark> custom({
    Expression<int>? id,
    Expression<int>? entryDate,
    Expression<String>? markType,
    Expression<String>? author,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryDate != null) 'entry_date': entryDate,
      if (markType != null) 'mark_type': markType,
      if (author != null) 'author': author,
    });
  }

  UserMarksCompanion copyWith(
      {Value<int>? id,
      Value<DateTime>? entryDate,
      Value<String>? markType,
      Value<String>? author}) {
    return UserMarksCompanion(
      id: id ?? this.id,
      entryDate: entryDate ?? this.entryDate,
      markType: markType ?? this.markType,
      author: author ?? this.author,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entryDate.present) {
      map['entry_date'] = Variable<int>(
          $UserMarksTable.$converterentryDate.toSql(entryDate.value));
    }
    if (markType.present) {
      map['mark_type'] = Variable<String>(markType.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserMarksCompanion(')
          ..write('id: $id, ')
          ..write('entryDate: $entryDate, ')
          ..write('markType: $markType, ')
          ..write('author: $author')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(Insertable<AppSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  /// Dot-namespaced setting identifier, e.g. 'locale', 'themeMode',
  /// 'temperatureRange', 'pdfExport.anonymize'.
  final String key;

  /// JSON-encoded setting value.
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory AppSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) => AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CycleDatabase extends GeneratedDatabase {
  _$CycleDatabase(QueryExecutor e) : super(e);
  $CycleDatabaseManager get managers => $CycleDatabaseManager(this);
  late final $CycleEntriesTable cycleEntries = $CycleEntriesTable(this);
  late final $UserMarksTable userMarks = $UserMarksTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final Index cycleEntriesDateUnique = Index('cycle_entries_date_unique',
      'CREATE UNIQUE INDEX cycle_entries_date_unique ON cycle_entries (date)');
  late final Index userMarksDateTypeUnique = Index(
      'user_marks_date_type_unique',
      'CREATE UNIQUE INDEX user_marks_date_type_unique ON user_marks (entry_date, mark_type)');
  late final EntriesDao entriesDao = EntriesDao(this as CycleDatabase);
  late final MarksDao marksDao = MarksDao(this as CycleDatabase);
  late final SettingsDao settingsDao = SettingsDao(this as CycleDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        cycleEntries,
        userMarks,
        appSettings,
        cycleEntriesDateUnique,
        userMarksDateTypeUnique
      ];
}

typedef $$CycleEntriesTableCreateCompanionBuilder = CycleEntriesCompanion
    Function({
  Value<int> id,
  required DateTime date,
  Value<int> tempDisturbances,
  Value<double?> bbtC,
  Value<int?> measuredAtMinutes,
  Value<Bleeding> bleeding,
  Value<String?> mucusSign,
  Value<String?> mucusQuality,
  Value<String?> cervixPosition,
  Value<String?> cervixOpening,
  Value<String?> cervixFirmness,
  Value<bool> painBreast,
  Value<bool> painMittelschmerz,
  Value<int> sexTimings,
  Value<String?> notes,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$CycleEntriesTableUpdateCompanionBuilder = CycleEntriesCompanion
    Function({
  Value<int> id,
  Value<DateTime> date,
  Value<int> tempDisturbances,
  Value<double?> bbtC,
  Value<int?> measuredAtMinutes,
  Value<Bleeding> bleeding,
  Value<String?> mucusSign,
  Value<String?> mucusQuality,
  Value<String?> cervixPosition,
  Value<String?> cervixOpening,
  Value<String?> cervixFirmness,
  Value<bool> painBreast,
  Value<bool> painMittelschmerz,
  Value<int> sexTimings,
  Value<String?> notes,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$CycleEntriesTableFilterComposer
    extends Composer<_$CycleDatabase, $CycleEntriesTable> {
  $$CycleEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get date =>
      $composableBuilder(
          column: $table.date,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<int> get tempDisturbances => $composableBuilder(
      column: $table.tempDisturbances,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get bbtC => $composableBuilder(
      column: $table.bbtC, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get measuredAtMinutes => $composableBuilder(
      column: $table.measuredAtMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<Bleeding, Bleeding, int> get bleeding =>
      $composableBuilder(
          column: $table.bleeding,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get mucusSign => $composableBuilder(
      column: $table.mucusSign, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mucusQuality => $composableBuilder(
      column: $table.mucusQuality, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cervixPosition => $composableBuilder(
      column: $table.cervixPosition,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cervixOpening => $composableBuilder(
      column: $table.cervixOpening, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cervixFirmness => $composableBuilder(
      column: $table.cervixFirmness,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get painBreast => $composableBuilder(
      column: $table.painBreast, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get painMittelschmerz => $composableBuilder(
      column: $table.painMittelschmerz,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sexTimings => $composableBuilder(
      column: $table.sexTimings, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CycleEntriesTableOrderingComposer
    extends Composer<_$CycleDatabase, $CycleEntriesTable> {
  $$CycleEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get tempDisturbances => $composableBuilder(
      column: $table.tempDisturbances,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get bbtC => $composableBuilder(
      column: $table.bbtC, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get measuredAtMinutes => $composableBuilder(
      column: $table.measuredAtMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bleeding => $composableBuilder(
      column: $table.bleeding, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mucusSign => $composableBuilder(
      column: $table.mucusSign, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mucusQuality => $composableBuilder(
      column: $table.mucusQuality,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cervixPosition => $composableBuilder(
      column: $table.cervixPosition,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cervixOpening => $composableBuilder(
      column: $table.cervixOpening,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cervixFirmness => $composableBuilder(
      column: $table.cervixFirmness,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get painBreast => $composableBuilder(
      column: $table.painBreast, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get painMittelschmerz => $composableBuilder(
      column: $table.painMittelschmerz,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sexTimings => $composableBuilder(
      column: $table.sexTimings, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CycleEntriesTableAnnotationComposer
    extends Composer<_$CycleDatabase, $CycleEntriesTable> {
  $$CycleEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get tempDisturbances => $composableBuilder(
      column: $table.tempDisturbances, builder: (column) => column);

  GeneratedColumn<double> get bbtC =>
      $composableBuilder(column: $table.bbtC, builder: (column) => column);

  GeneratedColumn<int> get measuredAtMinutes => $composableBuilder(
      column: $table.measuredAtMinutes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Bleeding, int> get bleeding =>
      $composableBuilder(column: $table.bleeding, builder: (column) => column);

  GeneratedColumn<String> get mucusSign =>
      $composableBuilder(column: $table.mucusSign, builder: (column) => column);

  GeneratedColumn<String> get mucusQuality => $composableBuilder(
      column: $table.mucusQuality, builder: (column) => column);

  GeneratedColumn<String> get cervixPosition => $composableBuilder(
      column: $table.cervixPosition, builder: (column) => column);

  GeneratedColumn<String> get cervixOpening => $composableBuilder(
      column: $table.cervixOpening, builder: (column) => column);

  GeneratedColumn<String> get cervixFirmness => $composableBuilder(
      column: $table.cervixFirmness, builder: (column) => column);

  GeneratedColumn<bool> get painBreast => $composableBuilder(
      column: $table.painBreast, builder: (column) => column);

  GeneratedColumn<bool> get painMittelschmerz => $composableBuilder(
      column: $table.painMittelschmerz, builder: (column) => column);

  GeneratedColumn<int> get sexTimings => $composableBuilder(
      column: $table.sexTimings, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CycleEntriesTableTableManager extends RootTableManager<
    _$CycleDatabase,
    $CycleEntriesTable,
    CycleEntry,
    $$CycleEntriesTableFilterComposer,
    $$CycleEntriesTableOrderingComposer,
    $$CycleEntriesTableAnnotationComposer,
    $$CycleEntriesTableCreateCompanionBuilder,
    $$CycleEntriesTableUpdateCompanionBuilder,
    (
      CycleEntry,
      BaseReferences<_$CycleDatabase, $CycleEntriesTable, CycleEntry>
    ),
    CycleEntry,
    PrefetchHooks Function()> {
  $$CycleEntriesTableTableManager(_$CycleDatabase db, $CycleEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CycleEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CycleEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CycleEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<DateTime> date = const Value.absent(),
            Value<int> tempDisturbances = const Value.absent(),
            Value<double?> bbtC = const Value.absent(),
            Value<int?> measuredAtMinutes = const Value.absent(),
            Value<Bleeding> bleeding = const Value.absent(),
            Value<String?> mucusSign = const Value.absent(),
            Value<String?> mucusQuality = const Value.absent(),
            Value<String?> cervixPosition = const Value.absent(),
            Value<String?> cervixOpening = const Value.absent(),
            Value<String?> cervixFirmness = const Value.absent(),
            Value<bool> painBreast = const Value.absent(),
            Value<bool> painMittelschmerz = const Value.absent(),
            Value<int> sexTimings = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              CycleEntriesCompanion(
            id: id,
            date: date,
            tempDisturbances: tempDisturbances,
            bbtC: bbtC,
            measuredAtMinutes: measuredAtMinutes,
            bleeding: bleeding,
            mucusSign: mucusSign,
            mucusQuality: mucusQuality,
            cervixPosition: cervixPosition,
            cervixOpening: cervixOpening,
            cervixFirmness: cervixFirmness,
            painBreast: painBreast,
            painMittelschmerz: painMittelschmerz,
            sexTimings: sexTimings,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required DateTime date,
            Value<int> tempDisturbances = const Value.absent(),
            Value<double?> bbtC = const Value.absent(),
            Value<int?> measuredAtMinutes = const Value.absent(),
            Value<Bleeding> bleeding = const Value.absent(),
            Value<String?> mucusSign = const Value.absent(),
            Value<String?> mucusQuality = const Value.absent(),
            Value<String?> cervixPosition = const Value.absent(),
            Value<String?> cervixOpening = const Value.absent(),
            Value<String?> cervixFirmness = const Value.absent(),
            Value<bool> painBreast = const Value.absent(),
            Value<bool> painMittelschmerz = const Value.absent(),
            Value<int> sexTimings = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              CycleEntriesCompanion.insert(
            id: id,
            date: date,
            tempDisturbances: tempDisturbances,
            bbtC: bbtC,
            measuredAtMinutes: measuredAtMinutes,
            bleeding: bleeding,
            mucusSign: mucusSign,
            mucusQuality: mucusQuality,
            cervixPosition: cervixPosition,
            cervixOpening: cervixOpening,
            cervixFirmness: cervixFirmness,
            painBreast: painBreast,
            painMittelschmerz: painMittelschmerz,
            sexTimings: sexTimings,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CycleEntriesTable, CycleEntry>(table),
                    BaseReferences<_$CycleDatabase, $CycleEntriesTable,
                        CycleEntry>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CycleEntriesTableProcessedTableManager = ProcessedTableManager<
    _$CycleDatabase,
    $CycleEntriesTable,
    CycleEntry,
    $$CycleEntriesTableFilterComposer,
    $$CycleEntriesTableOrderingComposer,
    $$CycleEntriesTableAnnotationComposer,
    $$CycleEntriesTableCreateCompanionBuilder,
    $$CycleEntriesTableUpdateCompanionBuilder,
    (
      CycleEntry,
      BaseReferences<_$CycleDatabase, $CycleEntriesTable, CycleEntry>
    ),
    CycleEntry,
    PrefetchHooks Function()>;
typedef $$UserMarksTableCreateCompanionBuilder = UserMarksCompanion Function({
  Value<int> id,
  required DateTime entryDate,
  required String markType,
  Value<String> author,
});
typedef $$UserMarksTableUpdateCompanionBuilder = UserMarksCompanion Function({
  Value<int> id,
  Value<DateTime> entryDate,
  Value<String> markType,
  Value<String> author,
});

class $$UserMarksTableFilterComposer
    extends Composer<_$CycleDatabase, $UserMarksTable> {
  $$UserMarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get entryDate =>
      $composableBuilder(
          column: $table.entryDate,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get markType => $composableBuilder(
      column: $table.markType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnFilters(column));
}

class $$UserMarksTableOrderingComposer
    extends Composer<_$CycleDatabase, $UserMarksTable> {
  $$UserMarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get entryDate => $composableBuilder(
      column: $table.entryDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get markType => $composableBuilder(
      column: $table.markType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnOrderings(column));
}

class $$UserMarksTableAnnotationComposer
    extends Composer<_$CycleDatabase, $UserMarksTable> {
  $$UserMarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get entryDate =>
      $composableBuilder(column: $table.entryDate, builder: (column) => column);

  GeneratedColumn<String> get markType =>
      $composableBuilder(column: $table.markType, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);
}

class $$UserMarksTableTableManager extends RootTableManager<
    _$CycleDatabase,
    $UserMarksTable,
    UserMark,
    $$UserMarksTableFilterComposer,
    $$UserMarksTableOrderingComposer,
    $$UserMarksTableAnnotationComposer,
    $$UserMarksTableCreateCompanionBuilder,
    $$UserMarksTableUpdateCompanionBuilder,
    (UserMark, BaseReferences<_$CycleDatabase, $UserMarksTable, UserMark>),
    UserMark,
    PrefetchHooks Function()> {
  $$UserMarksTableTableManager(_$CycleDatabase db, $UserMarksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserMarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserMarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserMarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<DateTime> entryDate = const Value.absent(),
            Value<String> markType = const Value.absent(),
            Value<String> author = const Value.absent(),
          }) =>
              UserMarksCompanion(
            id: id,
            entryDate: entryDate,
            markType: markType,
            author: author,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required DateTime entryDate,
            required String markType,
            Value<String> author = const Value.absent(),
          }) =>
              UserMarksCompanion.insert(
            id: id,
            entryDate: entryDate,
            markType: markType,
            author: author,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$UserMarksTable, UserMark>(table),
                    BaseReferences<_$CycleDatabase, $UserMarksTable, UserMark>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UserMarksTableProcessedTableManager = ProcessedTableManager<
    _$CycleDatabase,
    $UserMarksTable,
    UserMark,
    $$UserMarksTableFilterComposer,
    $$UserMarksTableOrderingComposer,
    $$UserMarksTableAnnotationComposer,
    $$UserMarksTableCreateCompanionBuilder,
    $$UserMarksTableUpdateCompanionBuilder,
    (UserMark, BaseReferences<_$CycleDatabase, $UserMarksTable, UserMark>),
    UserMark,
    PrefetchHooks Function()>;
typedef $$AppSettingsTableCreateCompanionBuilder = AppSettingsCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$AppSettingsTableUpdateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$AppSettingsTableFilterComposer
    extends Composer<_$CycleDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$CycleDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$CycleDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager extends RootTableManager<
    _$CycleDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      AppSetting,
      BaseReferences<_$CycleDatabase, $AppSettingsTable, AppSetting>
    ),
    AppSetting,
    PrefetchHooks Function()> {
  $$AppSettingsTableTableManager(_$CycleDatabase db, $AppSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$AppSettingsTable, AppSetting>(table),
                    BaseReferences<_$CycleDatabase, $AppSettingsTable,
                        AppSetting>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppSettingsTableProcessedTableManager = ProcessedTableManager<
    _$CycleDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      AppSetting,
      BaseReferences<_$CycleDatabase, $AppSettingsTable, AppSetting>
    ),
    AppSetting,
    PrefetchHooks Function()>;

class $CycleDatabaseManager {
  final _$CycleDatabase _db;
  $CycleDatabaseManager(this._db);
  $$CycleEntriesTableTableManager get cycleEntries =>
      $$CycleEntriesTableTableManager(_db, _db.cycleEntries);
  $$UserMarksTableTableManager get userMarks =>
      $$UserMarksTableTableManager(_db, _db.userMarks);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}

mixin _$EntriesDaoMixin on DatabaseAccessor<CycleDatabase> {
  $CycleEntriesTable get cycleEntries => attachedDatabase.cycleEntries;
  EntriesDaoManager get managers => EntriesDaoManager(this);
}

class EntriesDaoManager {
  final _$EntriesDaoMixin _db;
  EntriesDaoManager(this._db);
  $$CycleEntriesTableTableManager get cycleEntries =>
      $$CycleEntriesTableTableManager(_db.attachedDatabase, _db.cycleEntries);
}

mixin _$MarksDaoMixin on DatabaseAccessor<CycleDatabase> {
  $UserMarksTable get userMarks => attachedDatabase.userMarks;
  MarksDaoManager get managers => MarksDaoManager(this);
}

class MarksDaoManager {
  final _$MarksDaoMixin _db;
  MarksDaoManager(this._db);
  $$UserMarksTableTableManager get userMarks =>
      $$UserMarksTableTableManager(_db.attachedDatabase, _db.userMarks);
}

mixin _$SettingsDaoMixin on DatabaseAccessor<CycleDatabase> {
  $AppSettingsTable get appSettings => attachedDatabase.appSettings;
  SettingsDaoManager get managers => SettingsDaoManager(this);
}

class SettingsDaoManager {
  final _$SettingsDaoMixin _db;
  SettingsDaoManager(this._db);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db.attachedDatabase, _db.appSettings);
}
