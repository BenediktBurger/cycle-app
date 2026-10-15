// Shared fault-injection database for widget tests: a CycleDatabase over
// the standard in-memory connection whose individual reads and writes can
// be armed to fail AFTER a harness was pumped — the test flips a flag at
// exactly the point the fault should occur. Every fault defaults to off,
// so an unarmed instance behaves like the plain in-memory database.
import 'dart:async';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/measurement_method.dart';

import 'database.dart';

/// Fault injection over every database seam the widget tests arm:
///
/// - [failEntryReads] — entriesDao.allEntries (the delete-data pre-counts,
///   the export build, the import overwrite plan),
/// - [failWipe] — deleteAllTrackedData,
/// - [failMarkWrites] — every marksDao write (add/toggle/delete),
/// - [failMethodLoad] / [failMethodSave] / [failMethodDelete] — the
///   measurementMethodsDao load/upsert/delete.
///
/// [entryReadGate] additionally holds every entries read until the
/// completer resolves (import plan-timing control): the read — including
/// its armed failure — can only run once the test completes the gate.
/// Without a gate the armed entry-read failure throws before the read
/// starts.
final class FaultyCycleDatabase extends CycleDatabase {
  FaultyCycleDatabase({this.entryReadGate}) : super(inMemoryConnection());

  final Completer<void>? entryReadGate;

  bool failEntryReads = false;
  bool failWipe = false;
  bool failMarkWrites = false;
  bool failMethodLoad = false;
  bool failMethodSave = false;
  bool failMethodDelete = false;

  late final _FaultyEntriesDao _faultyEntriesDao = _FaultyEntriesDao(this);
  late final _FaultyMarksDao _faultyMarksDao = _FaultyMarksDao(this);
  late final _FaultyMethodsDao _faultyMethodsDao = _FaultyMethodsDao(this);

  @override
  EntriesDao get entriesDao => _faultyEntriesDao;

  @override
  MarksDao get marksDao => _faultyMarksDao;

  @override
  MeasurementMethodsDao get measurementMethodsDao => _faultyMethodsDao;

  @override
  Future<({int entries, int marks, int methods})> deleteAllTrackedData() {
    if (failWipe) {
      throw StateError('injected wipe failure');
    }
    return super.deleteAllTrackedData();
  }
}

final class _FaultyEntriesDao extends EntriesDao {
  _FaultyEntriesDao(this._faulty) : super(_faulty);

  final FaultyCycleDatabase _faulty;

  @override
  Future<List<CycleEntry>> allEntries() {
    final gate = _faulty.entryReadGate;
    if (gate == null) {
      if (_faulty.failEntryReads) {
        throw StateError('injected entry read failure');
      }
      return super.allEntries();
    }
    return gate.future.then((_) {
      if (_faulty.failEntryReads) {
        throw StateError('injected entry read failure');
      }
      return super.allEntries();
    });
  }
}

final class _FaultyMarksDao extends MarksDao {
  _FaultyMarksDao(this._faulty) : super(_faulty);

  final FaultyCycleDatabase _faulty;

  @override
  Future<UserMark> addMark(
    DateTime date,
    String markType, {
    String author = 'user',
  }) {
    if (_faulty.failMarkWrites) {
      throw StateError('injected mark write failure');
    }
    return super.addMark(date, markType, author: author);
  }

  @override
  Future<bool> toggleMark(DateTime date, String markType) {
    if (_faulty.failMarkWrites) {
      throw StateError('injected mark write failure');
    }
    return super.toggleMark(date, markType);
  }

  @override
  Future<int> deleteMark(DateTime date, String markType) {
    if (_faulty.failMarkWrites) {
      throw StateError('injected mark write failure');
    }
    return super.deleteMark(date, markType);
  }
}

final class _FaultyMethodsDao extends MeasurementMethodsDao {
  _FaultyMethodsDao(this._faulty) : super(_faulty);

  final FaultyCycleDatabase _faulty;

  @override
  Future<List<MeasurementMethod>> allSnapshots() {
    if (_faulty.failMethodLoad) {
      throw StateError('injected method load failure');
    }
    return super.allSnapshots();
  }

  @override
  Future<MeasurementMethod> upsertByDate({
    required DateTime date,
    required MeasurementRoute route,
    String? thermometer,
  }) {
    if (_faulty.failMethodSave) {
      throw StateError('injected method save failure');
    }
    return super.upsertByDate(
      date: date,
      route: route,
      thermometer: thermometer,
    );
  }

  @override
  Future<int> deleteByDate(DateTime date) {
    if (_faulty.failMethodDelete) {
      throw StateError('injected method delete failure');
    }
    return super.deleteByDate(date);
  }
}
