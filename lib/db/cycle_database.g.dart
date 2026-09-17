// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cycle_database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ordinalMeta =
      const VerificationMeta('ordinal');
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
      'ordinal', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [id, name, ordinal];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(Insertable<Profile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(_ordinalMeta,
          ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      ordinal: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ordinal'])!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  final int id;
  final String name;
  final int ordinal;
  const Profile({required this.id, required this.name, required this.ordinal});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['ordinal'] = Variable<int>(ordinal);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      name: Value(name),
      ordinal: Value(ordinal),
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'ordinal': serializer.toJson<int>(ordinal),
    };
  }

  Profile copyWith({int? id, String? name, int? ordinal}) => Profile(
        id: id ?? this.id,
        name: name ?? this.name,
        ordinal: ordinal ?? this.ordinal,
      );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('ordinal: $ordinal')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, ordinal);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.id == this.id &&
          other.name == this.name &&
          other.ordinal == this.ordinal);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> ordinal;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.ordinal = const Value.absent(),
  });
  ProfilesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.ordinal = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Profile> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? ordinal,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (ordinal != null) 'ordinal': ordinal,
    });
  }

  ProfilesCompanion copyWith(
      {Value<int>? id, Value<String>? name, Value<int>? ordinal}) {
    return ProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      ordinal: ordinal ?? this.ordinal,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('ordinal: $ordinal')
          ..write(')'))
        .toString();
  }
}

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
  static const VerificationMeta _profileIdMeta =
      const VerificationMeta('profileId');
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
      'profile_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES profiles (id)'),
      defaultValue: const Constant(1));
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> date =
      GeneratedColumn<int>('date', aliasedName, false,
              type: DriftSqlType.int, requiredDuringInsert: true)
          .withConverter<DateTime>($CycleEntriesTable.$converterdate);
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
  static const VerificationMeta _excludeIllnessMeta =
      const VerificationMeta('excludeIllness');
  @override
  late final GeneratedColumn<bool> excludeIllness = GeneratedColumn<bool>(
      'exclude_illness', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("exclude_illness" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _excludeAlcoholMeta =
      const VerificationMeta('excludeAlcohol');
  @override
  late final GeneratedColumn<bool> excludeAlcohol = GeneratedColumn<bool>(
      'exclude_alcohol', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("exclude_alcohol" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _excludeTravelMeta =
      const VerificationMeta('excludeTravel');
  @override
  late final GeneratedColumn<bool> excludeTravel = GeneratedColumn<bool>(
      'exclude_travel', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("exclude_travel" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _excludeOtherMeta =
      const VerificationMeta('excludeOther');
  @override
  late final GeneratedColumn<bool> excludeOther = GeneratedColumn<bool>(
      'exclude_other', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("exclude_other" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _mucusSignMeta =
      const VerificationMeta('mucusSign');
  @override
  late final GeneratedColumn<String> mucusSign = GeneratedColumn<String>(
      'mucus_sign', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints:
          'CHECK (mucus_sign IS NULL OR mucus_sign IN (\'t\', \'nothing\', \'f\', \'s\', \'a\'))');
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
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<bool> mood = GeneratedColumn<bool>(
      'mood', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("mood" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _desireMeta = const VerificationMeta('desire');
  @override
  late final GeneratedColumn<bool> desire = GeneratedColumn<bool>(
      'desire', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("desire" IN (0, 1))'),
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
        profileId,
        date,
        bbtC,
        measuredAtMinutes,
        bleeding,
        excludeIllness,
        excludeAlcohol,
        excludeTravel,
        excludeOther,
        mucusSign,
        mucusQuality,
        cervixPosition,
        cervixOpening,
        cervixFirmness,
        painBreast,
        painMittelschmerz,
        mood,
        desire,
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
    if (data.containsKey('profile_id')) {
      context.handle(_profileIdMeta,
          profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta));
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
    if (data.containsKey('exclude_illness')) {
      context.handle(
          _excludeIllnessMeta,
          excludeIllness.isAcceptableOrUnknown(
              data['exclude_illness']!, _excludeIllnessMeta));
    }
    if (data.containsKey('exclude_alcohol')) {
      context.handle(
          _excludeAlcoholMeta,
          excludeAlcohol.isAcceptableOrUnknown(
              data['exclude_alcohol']!, _excludeAlcoholMeta));
    }
    if (data.containsKey('exclude_travel')) {
      context.handle(
          _excludeTravelMeta,
          excludeTravel.isAcceptableOrUnknown(
              data['exclude_travel']!, _excludeTravelMeta));
    }
    if (data.containsKey('exclude_other')) {
      context.handle(
          _excludeOtherMeta,
          excludeOther.isAcceptableOrUnknown(
              data['exclude_other']!, _excludeOtherMeta));
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
    if (data.containsKey('mood')) {
      context.handle(
          _moodMeta, mood.isAcceptableOrUnknown(data['mood']!, _moodMeta));
    }
    if (data.containsKey('desire')) {
      context.handle(_desireMeta,
          desire.isAcceptableOrUnknown(data['desire']!, _desireMeta));
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
      profileId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}profile_id'])!,
      date: $CycleEntriesTable.$converterdate.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}date'])!),
      bbtC: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}bbt_c']),
      measuredAtMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}measured_at_minutes']),
      bleeding: $CycleEntriesTable.$converterbleeding.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bleeding'])!),
      excludeIllness: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}exclude_illness'])!,
      excludeAlcohol: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}exclude_alcohol'])!,
      excludeTravel: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}exclude_travel'])!,
      excludeOther: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}exclude_other'])!,
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
      mood: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}mood'])!,
      desire: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}desire'])!,
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

  /// FK to Profiles; defaults to the seeded main profile (id 1).
  final int profileId;

  /// Calendar day, stored as unix-epoch days (see EpochDayConverter).
  final DateTime date;

  /// Basal body temperature in degrees Celsius, when measured.
  final double? bbtC;

  /// Time-of-day of the temperature measurement, minutes since midnight
  /// (0–1439), NULL when not recorded. Engine-level CHECK mirrors the
  /// shared parse helper (lib/domain/models.dart) so foreign data (e.g. a
  /// future import path) cannot write an impossible time.
  final int? measuredAtMinutes;

  /// Bleeding intensity on the shared 5-step numeric scale, stored as the
  /// INTEGER [Bleeding.level]: none(0) / spotting(1) / light(2) / medium(3) /
  /// heavy(4). The converter derives every mapping from [Bleeding.level],
  /// never from the declaration index; an unknown stored number throws so
  /// corrupt data is surfaced instead of silently mapped. The default 0
  /// stores an explicit `none` (a day with no observation still has a value).
  final Bleeding bleeding;
  final bool excludeIllness;
  final bool excludeAlcohol;
  final bool excludeTravel;
  final bool excludeOther;

  /// Fertility sign recorded on the day: NULL when no observation, else one
  /// of the stable tokens 't' / 'nothing' / 'f' / 's' / 'a' (the MucusSign
  /// enum names — TEXT, unlike bleeding's numeric column; never display
  /// glyphs). customConstraint replaces drift's own constraints, which is
  /// fine here: SQLite columns admit NULL unless NOT NULL is written, and
  /// the check below allows exactly NULL or the vocabulary.
  final String? mucusSign;

  /// Quality qualifier of the mucus sign S; NULL for every sign other than
  /// 's' and for days without a sign. Enforced at the engine level so broken
  /// data (e.g. from a future import path) cannot be written.
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
  /// like the exclusion flags: plain booleans, no interval system.
  final bool painBreast;
  final bool painMittelschmerz;
  final bool mood;
  final bool desire;

  /// Times of day sex happened, as an INTEGER bitmask of [SexTiming.bit]:
  /// start(1) / middle(2) / end(4), OR-combined — multiple bits mean
  /// multiple times on the same day; 0 = not recorded. "Sex happened, time
  /// unknown" is deliberately NOT representable (the observation is only
  /// recorded together with a concrete time slot), so the mask fully
  /// replaces the former plain `sex` boolean. customConstraint replaces
  /// drift's own constraints, so NOT NULL and the column default 0 are
  /// written out explicitly inside the constraint string (a bare CHECK
  /// would silently drop both, leaving the column nullable).
  final int sexTimings;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CycleEntry(
      {required this.id,
      required this.profileId,
      required this.date,
      this.bbtC,
      this.measuredAtMinutes,
      required this.bleeding,
      required this.excludeIllness,
      required this.excludeAlcohol,
      required this.excludeTravel,
      required this.excludeOther,
      this.mucusSign,
      this.mucusQuality,
      this.cervixPosition,
      this.cervixOpening,
      this.cervixFirmness,
      required this.painBreast,
      required this.painMittelschmerz,
      required this.mood,
      required this.desire,
      required this.sexTimings,
      this.notes,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['profile_id'] = Variable<int>(profileId);
    {
      map['date'] =
          Variable<int>($CycleEntriesTable.$converterdate.toSql(date));
    }
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
    map['exclude_illness'] = Variable<bool>(excludeIllness);
    map['exclude_alcohol'] = Variable<bool>(excludeAlcohol);
    map['exclude_travel'] = Variable<bool>(excludeTravel);
    map['exclude_other'] = Variable<bool>(excludeOther);
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
    map['mood'] = Variable<bool>(mood);
    map['desire'] = Variable<bool>(desire);
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
      profileId: Value(profileId),
      date: Value(date),
      bbtC: bbtC == null && nullToAbsent ? const Value.absent() : Value(bbtC),
      measuredAtMinutes: measuredAtMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(measuredAtMinutes),
      bleeding: Value(bleeding),
      excludeIllness: Value(excludeIllness),
      excludeAlcohol: Value(excludeAlcohol),
      excludeTravel: Value(excludeTravel),
      excludeOther: Value(excludeOther),
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
      mood: Value(mood),
      desire: Value(desire),
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
      profileId: serializer.fromJson<int>(json['profileId']),
      date: serializer.fromJson<DateTime>(json['date']),
      bbtC: serializer.fromJson<double?>(json['bbtC']),
      measuredAtMinutes: serializer.fromJson<int?>(json['measuredAtMinutes']),
      bleeding: serializer.fromJson<Bleeding>(json['bleeding']),
      excludeIllness: serializer.fromJson<bool>(json['excludeIllness']),
      excludeAlcohol: serializer.fromJson<bool>(json['excludeAlcohol']),
      excludeTravel: serializer.fromJson<bool>(json['excludeTravel']),
      excludeOther: serializer.fromJson<bool>(json['excludeOther']),
      mucusSign: serializer.fromJson<String?>(json['mucusSign']),
      mucusQuality: serializer.fromJson<String?>(json['mucusQuality']),
      cervixPosition: serializer.fromJson<String?>(json['cervixPosition']),
      cervixOpening: serializer.fromJson<String?>(json['cervixOpening']),
      cervixFirmness: serializer.fromJson<String?>(json['cervixFirmness']),
      painBreast: serializer.fromJson<bool>(json['painBreast']),
      painMittelschmerz: serializer.fromJson<bool>(json['painMittelschmerz']),
      mood: serializer.fromJson<bool>(json['mood']),
      desire: serializer.fromJson<bool>(json['desire']),
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
      'profileId': serializer.toJson<int>(profileId),
      'date': serializer.toJson<DateTime>(date),
      'bbtC': serializer.toJson<double?>(bbtC),
      'measuredAtMinutes': serializer.toJson<int?>(measuredAtMinutes),
      'bleeding': serializer.toJson<Bleeding>(bleeding),
      'excludeIllness': serializer.toJson<bool>(excludeIllness),
      'excludeAlcohol': serializer.toJson<bool>(excludeAlcohol),
      'excludeTravel': serializer.toJson<bool>(excludeTravel),
      'excludeOther': serializer.toJson<bool>(excludeOther),
      'mucusSign': serializer.toJson<String?>(mucusSign),
      'mucusQuality': serializer.toJson<String?>(mucusQuality),
      'cervixPosition': serializer.toJson<String?>(cervixPosition),
      'cervixOpening': serializer.toJson<String?>(cervixOpening),
      'cervixFirmness': serializer.toJson<String?>(cervixFirmness),
      'painBreast': serializer.toJson<bool>(painBreast),
      'painMittelschmerz': serializer.toJson<bool>(painMittelschmerz),
      'mood': serializer.toJson<bool>(mood),
      'desire': serializer.toJson<bool>(desire),
      'sexTimings': serializer.toJson<int>(sexTimings),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CycleEntry copyWith(
          {int? id,
          int? profileId,
          DateTime? date,
          Value<double?> bbtC = const Value.absent(),
          Value<int?> measuredAtMinutes = const Value.absent(),
          Bleeding? bleeding,
          bool? excludeIllness,
          bool? excludeAlcohol,
          bool? excludeTravel,
          bool? excludeOther,
          Value<String?> mucusSign = const Value.absent(),
          Value<String?> mucusQuality = const Value.absent(),
          Value<String?> cervixPosition = const Value.absent(),
          Value<String?> cervixOpening = const Value.absent(),
          Value<String?> cervixFirmness = const Value.absent(),
          bool? painBreast,
          bool? painMittelschmerz,
          bool? mood,
          bool? desire,
          int? sexTimings,
          Value<String?> notes = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      CycleEntry(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        date: date ?? this.date,
        bbtC: bbtC.present ? bbtC.value : this.bbtC,
        measuredAtMinutes: measuredAtMinutes.present
            ? measuredAtMinutes.value
            : this.measuredAtMinutes,
        bleeding: bleeding ?? this.bleeding,
        excludeIllness: excludeIllness ?? this.excludeIllness,
        excludeAlcohol: excludeAlcohol ?? this.excludeAlcohol,
        excludeTravel: excludeTravel ?? this.excludeTravel,
        excludeOther: excludeOther ?? this.excludeOther,
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
        mood: mood ?? this.mood,
        desire: desire ?? this.desire,
        sexTimings: sexTimings ?? this.sexTimings,
        notes: notes.present ? notes.value : this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CycleEntry copyWithCompanion(CycleEntriesCompanion data) {
    return CycleEntry(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      date: data.date.present ? data.date.value : this.date,
      bbtC: data.bbtC.present ? data.bbtC.value : this.bbtC,
      measuredAtMinutes: data.measuredAtMinutes.present
          ? data.measuredAtMinutes.value
          : this.measuredAtMinutes,
      bleeding: data.bleeding.present ? data.bleeding.value : this.bleeding,
      excludeIllness: data.excludeIllness.present
          ? data.excludeIllness.value
          : this.excludeIllness,
      excludeAlcohol: data.excludeAlcohol.present
          ? data.excludeAlcohol.value
          : this.excludeAlcohol,
      excludeTravel: data.excludeTravel.present
          ? data.excludeTravel.value
          : this.excludeTravel,
      excludeOther: data.excludeOther.present
          ? data.excludeOther.value
          : this.excludeOther,
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
      mood: data.mood.present ? data.mood.value : this.mood,
      desire: data.desire.present ? data.desire.value : this.desire,
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
          ..write('profileId: $profileId, ')
          ..write('date: $date, ')
          ..write('bbtC: $bbtC, ')
          ..write('measuredAtMinutes: $measuredAtMinutes, ')
          ..write('bleeding: $bleeding, ')
          ..write('excludeIllness: $excludeIllness, ')
          ..write('excludeAlcohol: $excludeAlcohol, ')
          ..write('excludeTravel: $excludeTravel, ')
          ..write('excludeOther: $excludeOther, ')
          ..write('mucusSign: $mucusSign, ')
          ..write('mucusQuality: $mucusQuality, ')
          ..write('cervixPosition: $cervixPosition, ')
          ..write('cervixOpening: $cervixOpening, ')
          ..write('cervixFirmness: $cervixFirmness, ')
          ..write('painBreast: $painBreast, ')
          ..write('painMittelschmerz: $painMittelschmerz, ')
          ..write('mood: $mood, ')
          ..write('desire: $desire, ')
          ..write('sexTimings: $sexTimings, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        profileId,
        date,
        bbtC,
        measuredAtMinutes,
        bleeding,
        excludeIllness,
        excludeAlcohol,
        excludeTravel,
        excludeOther,
        mucusSign,
        mucusQuality,
        cervixPosition,
        cervixOpening,
        cervixFirmness,
        painBreast,
        painMittelschmerz,
        mood,
        desire,
        sexTimings,
        notes,
        createdAt,
        updatedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CycleEntry &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.date == this.date &&
          other.bbtC == this.bbtC &&
          other.measuredAtMinutes == this.measuredAtMinutes &&
          other.bleeding == this.bleeding &&
          other.excludeIllness == this.excludeIllness &&
          other.excludeAlcohol == this.excludeAlcohol &&
          other.excludeTravel == this.excludeTravel &&
          other.excludeOther == this.excludeOther &&
          other.mucusSign == this.mucusSign &&
          other.mucusQuality == this.mucusQuality &&
          other.cervixPosition == this.cervixPosition &&
          other.cervixOpening == this.cervixOpening &&
          other.cervixFirmness == this.cervixFirmness &&
          other.painBreast == this.painBreast &&
          other.painMittelschmerz == this.painMittelschmerz &&
          other.mood == this.mood &&
          other.desire == this.desire &&
          other.sexTimings == this.sexTimings &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CycleEntriesCompanion extends UpdateCompanion<CycleEntry> {
  final Value<int> id;
  final Value<int> profileId;
  final Value<DateTime> date;
  final Value<double?> bbtC;
  final Value<int?> measuredAtMinutes;
  final Value<Bleeding> bleeding;
  final Value<bool> excludeIllness;
  final Value<bool> excludeAlcohol;
  final Value<bool> excludeTravel;
  final Value<bool> excludeOther;
  final Value<String?> mucusSign;
  final Value<String?> mucusQuality;
  final Value<String?> cervixPosition;
  final Value<String?> cervixOpening;
  final Value<String?> cervixFirmness;
  final Value<bool> painBreast;
  final Value<bool> painMittelschmerz;
  final Value<bool> mood;
  final Value<bool> desire;
  final Value<int> sexTimings;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const CycleEntriesCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.date = const Value.absent(),
    this.bbtC = const Value.absent(),
    this.measuredAtMinutes = const Value.absent(),
    this.bleeding = const Value.absent(),
    this.excludeIllness = const Value.absent(),
    this.excludeAlcohol = const Value.absent(),
    this.excludeTravel = const Value.absent(),
    this.excludeOther = const Value.absent(),
    this.mucusSign = const Value.absent(),
    this.mucusQuality = const Value.absent(),
    this.cervixPosition = const Value.absent(),
    this.cervixOpening = const Value.absent(),
    this.cervixFirmness = const Value.absent(),
    this.painBreast = const Value.absent(),
    this.painMittelschmerz = const Value.absent(),
    this.mood = const Value.absent(),
    this.desire = const Value.absent(),
    this.sexTimings = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CycleEntriesCompanion.insert({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    required DateTime date,
    this.bbtC = const Value.absent(),
    this.measuredAtMinutes = const Value.absent(),
    this.bleeding = const Value.absent(),
    this.excludeIllness = const Value.absent(),
    this.excludeAlcohol = const Value.absent(),
    this.excludeTravel = const Value.absent(),
    this.excludeOther = const Value.absent(),
    this.mucusSign = const Value.absent(),
    this.mucusQuality = const Value.absent(),
    this.cervixPosition = const Value.absent(),
    this.cervixOpening = const Value.absent(),
    this.cervixFirmness = const Value.absent(),
    this.painBreast = const Value.absent(),
    this.painMittelschmerz = const Value.absent(),
    this.mood = const Value.absent(),
    this.desire = const Value.absent(),
    this.sexTimings = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : date = Value(date);
  static Insertable<CycleEntry> custom({
    Expression<int>? id,
    Expression<int>? profileId,
    Expression<int>? date,
    Expression<double>? bbtC,
    Expression<int>? measuredAtMinutes,
    Expression<int>? bleeding,
    Expression<bool>? excludeIllness,
    Expression<bool>? excludeAlcohol,
    Expression<bool>? excludeTravel,
    Expression<bool>? excludeOther,
    Expression<String>? mucusSign,
    Expression<String>? mucusQuality,
    Expression<String>? cervixPosition,
    Expression<String>? cervixOpening,
    Expression<String>? cervixFirmness,
    Expression<bool>? painBreast,
    Expression<bool>? painMittelschmerz,
    Expression<bool>? mood,
    Expression<bool>? desire,
    Expression<int>? sexTimings,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (date != null) 'date': date,
      if (bbtC != null) 'bbt_c': bbtC,
      if (measuredAtMinutes != null) 'measured_at_minutes': measuredAtMinutes,
      if (bleeding != null) 'bleeding': bleeding,
      if (excludeIllness != null) 'exclude_illness': excludeIllness,
      if (excludeAlcohol != null) 'exclude_alcohol': excludeAlcohol,
      if (excludeTravel != null) 'exclude_travel': excludeTravel,
      if (excludeOther != null) 'exclude_other': excludeOther,
      if (mucusSign != null) 'mucus_sign': mucusSign,
      if (mucusQuality != null) 'mucus_quality': mucusQuality,
      if (cervixPosition != null) 'cervix_position': cervixPosition,
      if (cervixOpening != null) 'cervix_opening': cervixOpening,
      if (cervixFirmness != null) 'cervix_firmness': cervixFirmness,
      if (painBreast != null) 'pain_breast': painBreast,
      if (painMittelschmerz != null) 'pain_mittelschmerz': painMittelschmerz,
      if (mood != null) 'mood': mood,
      if (desire != null) 'desire': desire,
      if (sexTimings != null) 'sex_timings': sexTimings,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CycleEntriesCompanion copyWith(
      {Value<int>? id,
      Value<int>? profileId,
      Value<DateTime>? date,
      Value<double?>? bbtC,
      Value<int?>? measuredAtMinutes,
      Value<Bleeding>? bleeding,
      Value<bool>? excludeIllness,
      Value<bool>? excludeAlcohol,
      Value<bool>? excludeTravel,
      Value<bool>? excludeOther,
      Value<String?>? mucusSign,
      Value<String?>? mucusQuality,
      Value<String?>? cervixPosition,
      Value<String?>? cervixOpening,
      Value<String?>? cervixFirmness,
      Value<bool>? painBreast,
      Value<bool>? painMittelschmerz,
      Value<bool>? mood,
      Value<bool>? desire,
      Value<int>? sexTimings,
      Value<String?>? notes,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return CycleEntriesCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      date: date ?? this.date,
      bbtC: bbtC ?? this.bbtC,
      measuredAtMinutes: measuredAtMinutes ?? this.measuredAtMinutes,
      bleeding: bleeding ?? this.bleeding,
      excludeIllness: excludeIllness ?? this.excludeIllness,
      excludeAlcohol: excludeAlcohol ?? this.excludeAlcohol,
      excludeTravel: excludeTravel ?? this.excludeTravel,
      excludeOther: excludeOther ?? this.excludeOther,
      mucusSign: mucusSign ?? this.mucusSign,
      mucusQuality: mucusQuality ?? this.mucusQuality,
      cervixPosition: cervixPosition ?? this.cervixPosition,
      cervixOpening: cervixOpening ?? this.cervixOpening,
      cervixFirmness: cervixFirmness ?? this.cervixFirmness,
      painBreast: painBreast ?? this.painBreast,
      painMittelschmerz: painMittelschmerz ?? this.painMittelschmerz,
      mood: mood ?? this.mood,
      desire: desire ?? this.desire,
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
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
    }
    if (date.present) {
      map['date'] =
          Variable<int>($CycleEntriesTable.$converterdate.toSql(date.value));
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
    if (excludeIllness.present) {
      map['exclude_illness'] = Variable<bool>(excludeIllness.value);
    }
    if (excludeAlcohol.present) {
      map['exclude_alcohol'] = Variable<bool>(excludeAlcohol.value);
    }
    if (excludeTravel.present) {
      map['exclude_travel'] = Variable<bool>(excludeTravel.value);
    }
    if (excludeOther.present) {
      map['exclude_other'] = Variable<bool>(excludeOther.value);
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
    if (mood.present) {
      map['mood'] = Variable<bool>(mood.value);
    }
    if (desire.present) {
      map['desire'] = Variable<bool>(desire.value);
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
          ..write('profileId: $profileId, ')
          ..write('date: $date, ')
          ..write('bbtC: $bbtC, ')
          ..write('measuredAtMinutes: $measuredAtMinutes, ')
          ..write('bleeding: $bleeding, ')
          ..write('excludeIllness: $excludeIllness, ')
          ..write('excludeAlcohol: $excludeAlcohol, ')
          ..write('excludeTravel: $excludeTravel, ')
          ..write('excludeOther: $excludeOther, ')
          ..write('mucusSign: $mucusSign, ')
          ..write('mucusQuality: $mucusQuality, ')
          ..write('cervixPosition: $cervixPosition, ')
          ..write('cervixOpening: $cervixOpening, ')
          ..write('cervixFirmness: $cervixFirmness, ')
          ..write('painBreast: $painBreast, ')
          ..write('painMittelschmerz: $painMittelschmerz, ')
          ..write('mood: $mood, ')
          ..write('desire: $desire, ')
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
  static const VerificationMeta _profileIdMeta =
      const VerificationMeta('profileId');
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
      'profile_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES profiles (id)'),
      defaultValue: const Constant(1));
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
  List<GeneratedColumn> get $columns =>
      [id, profileId, entryDate, markType, author];
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
    if (data.containsKey('profile_id')) {
      context.handle(_profileIdMeta,
          profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta));
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
      profileId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}profile_id'])!,
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
  final int profileId;

  /// Calendar day the mark belongs to (unix-epoch days).
  final DateTime entryDate;

  /// Marking tool identifier, e.g. one of the [MarkTypes] constants.
  final String markType;

  /// Who placed the mark. 'user' today; later milestones may add modes
  /// (e.g. an 'assist' author for Mode-S suggestions — deliberately kept
  /// open TEXT instead of constraining to an enum).
  final String author;
  const UserMark(
      {required this.id,
      required this.profileId,
      required this.entryDate,
      required this.markType,
      required this.author});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['profile_id'] = Variable<int>(profileId);
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
      profileId: Value(profileId),
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
      profileId: serializer.fromJson<int>(json['profileId']),
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
      'profileId': serializer.toJson<int>(profileId),
      'entryDate': serializer.toJson<DateTime>(entryDate),
      'markType': serializer.toJson<String>(markType),
      'author': serializer.toJson<String>(author),
    };
  }

  UserMark copyWith(
          {int? id,
          int? profileId,
          DateTime? entryDate,
          String? markType,
          String? author}) =>
      UserMark(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        entryDate: entryDate ?? this.entryDate,
        markType: markType ?? this.markType,
        author: author ?? this.author,
      );
  UserMark copyWithCompanion(UserMarksCompanion data) {
    return UserMark(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      entryDate: data.entryDate.present ? data.entryDate.value : this.entryDate,
      markType: data.markType.present ? data.markType.value : this.markType,
      author: data.author.present ? data.author.value : this.author,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserMark(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('entryDate: $entryDate, ')
          ..write('markType: $markType, ')
          ..write('author: $author')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, profileId, entryDate, markType, author);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserMark &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.entryDate == this.entryDate &&
          other.markType == this.markType &&
          other.author == this.author);
}

class UserMarksCompanion extends UpdateCompanion<UserMark> {
  final Value<int> id;
  final Value<int> profileId;
  final Value<DateTime> entryDate;
  final Value<String> markType;
  final Value<String> author;
  const UserMarksCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.entryDate = const Value.absent(),
    this.markType = const Value.absent(),
    this.author = const Value.absent(),
  });
  UserMarksCompanion.insert({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    required DateTime entryDate,
    required String markType,
    this.author = const Value.absent(),
  })  : entryDate = Value(entryDate),
        markType = Value(markType);
  static Insertable<UserMark> custom({
    Expression<int>? id,
    Expression<int>? profileId,
    Expression<int>? entryDate,
    Expression<String>? markType,
    Expression<String>? author,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (entryDate != null) 'entry_date': entryDate,
      if (markType != null) 'mark_type': markType,
      if (author != null) 'author': author,
    });
  }

  UserMarksCompanion copyWith(
      {Value<int>? id,
      Value<int>? profileId,
      Value<DateTime>? entryDate,
      Value<String>? markType,
      Value<String>? author}) {
    return UserMarksCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
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
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
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
          ..write('profileId: $profileId, ')
          ..write('entryDate: $entryDate, ')
          ..write('markType: $markType, ')
          ..write('author: $author')
          ..write(')'))
        .toString();
  }
}

abstract class _$CycleDatabase extends GeneratedDatabase {
  _$CycleDatabase(QueryExecutor e) : super(e);
  $CycleDatabaseManager get managers => $CycleDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $CycleEntriesTable cycleEntries = $CycleEntriesTable(this);
  late final $UserMarksTable userMarks = $UserMarksTable(this);
  late final Index cycleEntriesProfileDateUnique = Index(
      'cycle_entries_profile_date_unique',
      'CREATE UNIQUE INDEX cycle_entries_profile_date_unique ON cycle_entries (profile_id, date)');
  late final Index userMarksProfileDateTypeUnique = Index(
      'user_marks_profile_date_type_unique',
      'CREATE UNIQUE INDEX user_marks_profile_date_type_unique ON user_marks (profile_id, entry_date, mark_type)');
  late final EntriesDao entriesDao = EntriesDao(this as CycleDatabase);
  late final MarksDao marksDao = MarksDao(this as CycleDatabase);
  late final ProfilesDao profilesDao = ProfilesDao(this as CycleDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        profiles,
        cycleEntries,
        userMarks,
        cycleEntriesProfileDateUnique,
        userMarksProfileDateTypeUnique
      ];
}

typedef $$ProfilesTableCreateCompanionBuilder = ProfilesCompanion Function({
  Value<int> id,
  required String name,
  Value<int> ordinal,
});
typedef $$ProfilesTableUpdateCompanionBuilder = ProfilesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> ordinal,
});

final class $$ProfilesTableReferences
    extends BaseReferences<_$CycleDatabase, $ProfilesTable, Profile> {
  $$ProfilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CycleEntriesTable, List<CycleEntry>>
      _cycleEntriesRefsTable(_$CycleDatabase db) =>
          MultiTypedResultKey.fromTable(db.cycleEntries,
              aliasName: 'profiles__id__cycle_entries__profile_id');

  $$CycleEntriesTableProcessedTableManager get cycleEntriesRefs {
    final manager = $$CycleEntriesTableTableManager($_db, $_db.cycleEntries)
        .filter((f) => f.profileId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_cycleEntriesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$UserMarksTable, List<UserMark>>
      _userMarksRefsTable(_$CycleDatabase db) =>
          MultiTypedResultKey.fromTable(db.userMarks,
              aliasName: 'profiles__id__user_marks__profile_id');

  $$UserMarksTableProcessedTableManager get userMarksRefs {
    final manager = $$UserMarksTableTableManager($_db, $_db.userMarks)
        .filter((f) => f.profileId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_userMarksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProfilesTableFilterComposer
    extends Composer<_$CycleDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ordinal => $composableBuilder(
      column: $table.ordinal, builder: (column) => ColumnFilters(column));

  Expression<bool> cycleEntriesRefs(
      Expression<bool> Function($$CycleEntriesTableFilterComposer f) f) {
    final $$CycleEntriesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.cycleEntries,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CycleEntriesTableFilterComposer(
              $db: $db,
              $table: $db.cycleEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> userMarksRefs(
      Expression<bool> Function($$UserMarksTableFilterComposer f) f) {
    final $$UserMarksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.userMarks,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$UserMarksTableFilterComposer(
              $db: $db,
              $table: $db.userMarks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$CycleDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ordinal => $composableBuilder(
      column: $table.ordinal, builder: (column) => ColumnOrderings(column));
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$CycleDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  Expression<T> cycleEntriesRefs<T extends Object>(
      Expression<T> Function($$CycleEntriesTableAnnotationComposer a) f) {
    final $$CycleEntriesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.cycleEntries,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CycleEntriesTableAnnotationComposer(
              $db: $db,
              $table: $db.cycleEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> userMarksRefs<T extends Object>(
      Expression<T> Function($$UserMarksTableAnnotationComposer a) f) {
    final $$UserMarksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.userMarks,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$UserMarksTableAnnotationComposer(
              $db: $db,
              $table: $db.userMarks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProfilesTableTableManager extends RootTableManager<
    _$CycleDatabase,
    $ProfilesTable,
    Profile,
    $$ProfilesTableFilterComposer,
    $$ProfilesTableOrderingComposer,
    $$ProfilesTableAnnotationComposer,
    $$ProfilesTableCreateCompanionBuilder,
    $$ProfilesTableUpdateCompanionBuilder,
    (Profile, $$ProfilesTableReferences),
    Profile,
    PrefetchHooks Function({bool cycleEntriesRefs, bool userMarksRefs})> {
  $$ProfilesTableTableManager(_$CycleDatabase db, $ProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> ordinal = const Value.absent(),
          }) =>
              ProfilesCompanion(
            id: id,
            name: name,
            ordinal: ordinal,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<int> ordinal = const Value.absent(),
          }) =>
              ProfilesCompanion.insert(
            id: id,
            name: name,
            ordinal: ordinal,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ProfilesTable, Profile>(table),
                    $$ProfilesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {cycleEntriesRefs = false, userMarksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (cycleEntriesRefs) db.cycleEntries,
                if (userMarksRefs) db.userMarks
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (cycleEntriesRefs)
                    await $_getPrefetchedData<Profile, $ProfilesTable,
                            CycleEntry>(
                        currentTable: table,
                        referencedTable: $$ProfilesTableReferences
                            ._cycleEntriesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProfilesTableReferences(db, table, p0)
                                .cycleEntriesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.profileId == item.id),
                        typedResults: items),
                  if (userMarksRefs)
                    await $_getPrefetchedData<Profile, $ProfilesTable,
                            UserMark>(
                        currentTable: table,
                        referencedTable:
                            $$ProfilesTableReferences._userMarksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProfilesTableReferences(db, table, p0)
                                .userMarksRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.profileId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProfilesTableProcessedTableManager = ProcessedTableManager<
    _$CycleDatabase,
    $ProfilesTable,
    Profile,
    $$ProfilesTableFilterComposer,
    $$ProfilesTableOrderingComposer,
    $$ProfilesTableAnnotationComposer,
    $$ProfilesTableCreateCompanionBuilder,
    $$ProfilesTableUpdateCompanionBuilder,
    (Profile, $$ProfilesTableReferences),
    Profile,
    PrefetchHooks Function({bool cycleEntriesRefs, bool userMarksRefs})>;
typedef $$CycleEntriesTableCreateCompanionBuilder = CycleEntriesCompanion
    Function({
  Value<int> id,
  Value<int> profileId,
  required DateTime date,
  Value<double?> bbtC,
  Value<int?> measuredAtMinutes,
  Value<Bleeding> bleeding,
  Value<bool> excludeIllness,
  Value<bool> excludeAlcohol,
  Value<bool> excludeTravel,
  Value<bool> excludeOther,
  Value<String?> mucusSign,
  Value<String?> mucusQuality,
  Value<String?> cervixPosition,
  Value<String?> cervixOpening,
  Value<String?> cervixFirmness,
  Value<bool> painBreast,
  Value<bool> painMittelschmerz,
  Value<bool> mood,
  Value<bool> desire,
  Value<int> sexTimings,
  Value<String?> notes,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$CycleEntriesTableUpdateCompanionBuilder = CycleEntriesCompanion
    Function({
  Value<int> id,
  Value<int> profileId,
  Value<DateTime> date,
  Value<double?> bbtC,
  Value<int?> measuredAtMinutes,
  Value<Bleeding> bleeding,
  Value<bool> excludeIllness,
  Value<bool> excludeAlcohol,
  Value<bool> excludeTravel,
  Value<bool> excludeOther,
  Value<String?> mucusSign,
  Value<String?> mucusQuality,
  Value<String?> cervixPosition,
  Value<String?> cervixOpening,
  Value<String?> cervixFirmness,
  Value<bool> painBreast,
  Value<bool> painMittelschmerz,
  Value<bool> mood,
  Value<bool> desire,
  Value<int> sexTimings,
  Value<String?> notes,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$CycleEntriesTableReferences
    extends BaseReferences<_$CycleDatabase, $CycleEntriesTable, CycleEntry> {
  $$CycleEntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileIdTable(_$CycleDatabase db) =>
      db.profiles.createAlias('cycle_entries__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<int>('profile_id')!;

    final manager = $$ProfilesTableTableManager($_db, $_db.profiles)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

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

  ColumnFilters<double> get bbtC => $composableBuilder(
      column: $table.bbtC, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get measuredAtMinutes => $composableBuilder(
      column: $table.measuredAtMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<Bleeding, Bleeding, int> get bleeding =>
      $composableBuilder(
          column: $table.bleeding,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<bool> get excludeIllness => $composableBuilder(
      column: $table.excludeIllness,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get excludeAlcohol => $composableBuilder(
      column: $table.excludeAlcohol,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get excludeTravel => $composableBuilder(
      column: $table.excludeTravel, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get excludeOther => $composableBuilder(
      column: $table.excludeOther, builder: (column) => ColumnFilters(column));

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

  ColumnFilters<bool> get mood => $composableBuilder(
      column: $table.mood, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get desire => $composableBuilder(
      column: $table.desire, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sexTimings => $composableBuilder(
      column: $table.sexTimings, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableFilterComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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

  ColumnOrderings<double> get bbtC => $composableBuilder(
      column: $table.bbtC, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get measuredAtMinutes => $composableBuilder(
      column: $table.measuredAtMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bleeding => $composableBuilder(
      column: $table.bleeding, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get excludeIllness => $composableBuilder(
      column: $table.excludeIllness,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get excludeAlcohol => $composableBuilder(
      column: $table.excludeAlcohol,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get excludeTravel => $composableBuilder(
      column: $table.excludeTravel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get excludeOther => $composableBuilder(
      column: $table.excludeOther,
      builder: (column) => ColumnOrderings(column));

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

  ColumnOrderings<bool> get mood => $composableBuilder(
      column: $table.mood, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get desire => $composableBuilder(
      column: $table.desire, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sexTimings => $composableBuilder(
      column: $table.sexTimings, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableOrderingComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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

  GeneratedColumn<double> get bbtC =>
      $composableBuilder(column: $table.bbtC, builder: (column) => column);

  GeneratedColumn<int> get measuredAtMinutes => $composableBuilder(
      column: $table.measuredAtMinutes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Bleeding, int> get bleeding =>
      $composableBuilder(column: $table.bleeding, builder: (column) => column);

  GeneratedColumn<bool> get excludeIllness => $composableBuilder(
      column: $table.excludeIllness, builder: (column) => column);

  GeneratedColumn<bool> get excludeAlcohol => $composableBuilder(
      column: $table.excludeAlcohol, builder: (column) => column);

  GeneratedColumn<bool> get excludeTravel => $composableBuilder(
      column: $table.excludeTravel, builder: (column) => column);

  GeneratedColumn<bool> get excludeOther => $composableBuilder(
      column: $table.excludeOther, builder: (column) => column);

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

  GeneratedColumn<bool> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<bool> get desire =>
      $composableBuilder(column: $table.desire, builder: (column) => column);

  GeneratedColumn<int> get sexTimings => $composableBuilder(
      column: $table.sexTimings, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableAnnotationComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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
    (CycleEntry, $$CycleEntriesTableReferences),
    CycleEntry,
    PrefetchHooks Function({bool profileId})> {
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
            Value<int> profileId = const Value.absent(),
            Value<DateTime> date = const Value.absent(),
            Value<double?> bbtC = const Value.absent(),
            Value<int?> measuredAtMinutes = const Value.absent(),
            Value<Bleeding> bleeding = const Value.absent(),
            Value<bool> excludeIllness = const Value.absent(),
            Value<bool> excludeAlcohol = const Value.absent(),
            Value<bool> excludeTravel = const Value.absent(),
            Value<bool> excludeOther = const Value.absent(),
            Value<String?> mucusSign = const Value.absent(),
            Value<String?> mucusQuality = const Value.absent(),
            Value<String?> cervixPosition = const Value.absent(),
            Value<String?> cervixOpening = const Value.absent(),
            Value<String?> cervixFirmness = const Value.absent(),
            Value<bool> painBreast = const Value.absent(),
            Value<bool> painMittelschmerz = const Value.absent(),
            Value<bool> mood = const Value.absent(),
            Value<bool> desire = const Value.absent(),
            Value<int> sexTimings = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              CycleEntriesCompanion(
            id: id,
            profileId: profileId,
            date: date,
            bbtC: bbtC,
            measuredAtMinutes: measuredAtMinutes,
            bleeding: bleeding,
            excludeIllness: excludeIllness,
            excludeAlcohol: excludeAlcohol,
            excludeTravel: excludeTravel,
            excludeOther: excludeOther,
            mucusSign: mucusSign,
            mucusQuality: mucusQuality,
            cervixPosition: cervixPosition,
            cervixOpening: cervixOpening,
            cervixFirmness: cervixFirmness,
            painBreast: painBreast,
            painMittelschmerz: painMittelschmerz,
            mood: mood,
            desire: desire,
            sexTimings: sexTimings,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> profileId = const Value.absent(),
            required DateTime date,
            Value<double?> bbtC = const Value.absent(),
            Value<int?> measuredAtMinutes = const Value.absent(),
            Value<Bleeding> bleeding = const Value.absent(),
            Value<bool> excludeIllness = const Value.absent(),
            Value<bool> excludeAlcohol = const Value.absent(),
            Value<bool> excludeTravel = const Value.absent(),
            Value<bool> excludeOther = const Value.absent(),
            Value<String?> mucusSign = const Value.absent(),
            Value<String?> mucusQuality = const Value.absent(),
            Value<String?> cervixPosition = const Value.absent(),
            Value<String?> cervixOpening = const Value.absent(),
            Value<String?> cervixFirmness = const Value.absent(),
            Value<bool> painBreast = const Value.absent(),
            Value<bool> painMittelschmerz = const Value.absent(),
            Value<bool> mood = const Value.absent(),
            Value<bool> desire = const Value.absent(),
            Value<int> sexTimings = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              CycleEntriesCompanion.insert(
            id: id,
            profileId: profileId,
            date: date,
            bbtC: bbtC,
            measuredAtMinutes: measuredAtMinutes,
            bleeding: bleeding,
            excludeIllness: excludeIllness,
            excludeAlcohol: excludeAlcohol,
            excludeTravel: excludeTravel,
            excludeOther: excludeOther,
            mucusSign: mucusSign,
            mucusQuality: mucusQuality,
            cervixPosition: cervixPosition,
            cervixOpening: cervixOpening,
            cervixFirmness: cervixFirmness,
            painBreast: painBreast,
            painMittelschmerz: painMittelschmerz,
            mood: mood,
            desire: desire,
            sexTimings: sexTimings,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CycleEntriesTable, CycleEntry>(table),
                    $$CycleEntriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (profileId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.profileId,
                    referencedTable:
                        $$CycleEntriesTableReferences._profileIdTable(db),
                    referencedColumn:
                        $$CycleEntriesTableReferences._profileIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
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
    (CycleEntry, $$CycleEntriesTableReferences),
    CycleEntry,
    PrefetchHooks Function({bool profileId})>;
typedef $$UserMarksTableCreateCompanionBuilder = UserMarksCompanion Function({
  Value<int> id,
  Value<int> profileId,
  required DateTime entryDate,
  required String markType,
  Value<String> author,
});
typedef $$UserMarksTableUpdateCompanionBuilder = UserMarksCompanion Function({
  Value<int> id,
  Value<int> profileId,
  Value<DateTime> entryDate,
  Value<String> markType,
  Value<String> author,
});

final class $$UserMarksTableReferences
    extends BaseReferences<_$CycleDatabase, $UserMarksTable, UserMark> {
  $$UserMarksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileIdTable(_$CycleDatabase db) =>
      db.profiles.createAlias('user_marks__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<int>('profile_id')!;

    final manager = $$ProfilesTableTableManager($_db, $_db.profiles)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

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

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableFilterComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableOrderingComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableAnnotationComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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
    (UserMark, $$UserMarksTableReferences),
    UserMark,
    PrefetchHooks Function({bool profileId})> {
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
            Value<int> profileId = const Value.absent(),
            Value<DateTime> entryDate = const Value.absent(),
            Value<String> markType = const Value.absent(),
            Value<String> author = const Value.absent(),
          }) =>
              UserMarksCompanion(
            id: id,
            profileId: profileId,
            entryDate: entryDate,
            markType: markType,
            author: author,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> profileId = const Value.absent(),
            required DateTime entryDate,
            required String markType,
            Value<String> author = const Value.absent(),
          }) =>
              UserMarksCompanion.insert(
            id: id,
            profileId: profileId,
            entryDate: entryDate,
            markType: markType,
            author: author,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$UserMarksTable, UserMark>(table),
                    $$UserMarksTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (profileId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.profileId,
                    referencedTable:
                        $$UserMarksTableReferences._profileIdTable(db),
                    referencedColumn:
                        $$UserMarksTableReferences._profileIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
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
    (UserMark, $$UserMarksTableReferences),
    UserMark,
    PrefetchHooks Function({bool profileId})>;

class $CycleDatabaseManager {
  final _$CycleDatabase _db;
  $CycleDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$CycleEntriesTableTableManager get cycleEntries =>
      $$CycleEntriesTableTableManager(_db, _db.cycleEntries);
  $$UserMarksTableTableManager get userMarks =>
      $$UserMarksTableTableManager(_db, _db.userMarks);
}

mixin _$EntriesDaoMixin on DatabaseAccessor<CycleDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $CycleEntriesTable get cycleEntries => attachedDatabase.cycleEntries;
  EntriesDaoManager get managers => EntriesDaoManager(this);
}

class EntriesDaoManager {
  final _$EntriesDaoMixin _db;
  EntriesDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$CycleEntriesTableTableManager get cycleEntries =>
      $$CycleEntriesTableTableManager(_db.attachedDatabase, _db.cycleEntries);
}

mixin _$MarksDaoMixin on DatabaseAccessor<CycleDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $UserMarksTable get userMarks => attachedDatabase.userMarks;
  MarksDaoManager get managers => MarksDaoManager(this);
}

class MarksDaoManager {
  final _$MarksDaoMixin _db;
  MarksDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$UserMarksTableTableManager get userMarks =>
      $$UserMarksTableTableManager(_db.attachedDatabase, _db.userMarks);
}

mixin _$ProfilesDaoMixin on DatabaseAccessor<CycleDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  ProfilesDaoManager get managers => ProfilesDaoManager(this);
}

class ProfilesDaoManager {
  final _$ProfilesDaoMixin _db;
  ProfilesDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
}
