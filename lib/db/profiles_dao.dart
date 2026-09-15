// ProfilesDao: profile listing for the (later-UI) partner mode.
// Part of the cycle_database.dart library — see its header.

part of 'cycle_database.dart';

@DriftAccessor(tables: [Profiles])
class ProfilesDao extends DatabaseAccessor<CycleDatabase>
    with _$ProfilesDaoMixin {
  ProfilesDao(super.db);

  /// All profiles, ordered by ordinal then id.
  Future<List<Profile>> allProfiles() {
    return (select(profiles)..orderBy([(t) => OrderingTerm.asc(t.ordinal)]))
        .get();
  }

  /// Live stream of profiles, ordered by ordinal then id.
  Stream<List<Profile>> watchProfiles() {
    return (select(profiles)..orderBy([(t) => OrderingTerm.asc(t.ordinal)]))
        .watch();
  }

  /// Just the profile names, in ordinal order.
  Future<List<String>> profileNames() async {
    final rows = await allProfiles();
    return rows.map((p) => p.name).toList();
  }

  /// Single profile lookup, or null.
  Future<Profile?> byId(int id) {
    return (select(profiles)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Adds a new profile and returns it.
  Future<Profile> addProfile(String name, {int? ordinal}) {
    final companion = ProfilesCompanion.insert(name: name);
    return into(profiles).insertReturning(ordinal == null
        ? companion
        : companion.copyWith(
            ordinal: Value(ordinal),
          ));
  }
}
