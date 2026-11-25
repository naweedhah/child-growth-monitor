import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

/// A child with their measurements, newest last.
class ChildWithMeasurements {
  const ChildWithMeasurements(this.child, this.measurements);

  final Child child;
  final List<Measurement> measurements;

  Measurement? get latest => measurements.isEmpty ? null : measurements.last;
  Measurement? get previous => measurements.length < 2 ? null : measurements[measurements.length - 2];
}

/// All local reads and writes. Every write marks the record dirty and stamps `updatedAt`, so
/// the sync engine knows what to upload. The UI only ever talks to this local database, which
/// is why the app works the same with or without a signal.
class GrowthRepository {
  GrowthRepository(this.db, {DateTime Function()? clock, Uuid? uuid})
      : _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final DateTime Function() _clock;
  final Uuid _uuid;

  /// The whole caseload with measurements, refreshed whenever either table changes.
  Stream<List<ChildWithMeasurements>> watchCaseload() async* {
    yield await loadCaseload();
    await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables([db.children, db.measurements]))) {
      yield await loadCaseload();
    }
  }

  Future<List<ChildWithMeasurements>> loadCaseload() async {
    final children = await (db.select(db.children)
          ..where((c) => c.deleted.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
    final measurements = await (db.select(db.measurements)
          ..where((m) => m.deleted.equals(false))
          ..orderBy([(m) => OrderingTerm.asc(m.measuredOn)]))
        .get();
    final byChild = <String, List<Measurement>>{};
    for (final m in measurements) {
      byChild.putIfAbsent(m.childId, () => []).add(m);
    }
    return [for (final c in children) ChildWithMeasurements(c, byChild[c.id] ?? const [])];
  }

  Stream<ChildWithMeasurements?> watchChild(String id) =>
      watchCaseload().map((all) => all.where((c) => c.child.id == id).firstOrNull);

  Future<String> saveChild({
    String? id,
    required String name,
    required String sex,
    required DateTime dateOfBirth,
    required String guardianName,
    String? guardianPhone,
    required String area,
    String? notes,
  }) async {
    final childId = id ?? _uuid.v4();
    final values = ChildrenCompanion(
      name: Value(name.trim()),
      sex: Value(sex),
      dateOfBirth: Value(DateTime.utc(dateOfBirth.year, dateOfBirth.month, dateOfBirth.day)),
      guardianName: Value(guardianName.trim()),
      guardianPhone: Value(_blankToNull(guardianPhone)),
      area: Value(area.trim()),
      notes: Value(_blankToNull(notes)),
      updatedAt: Value(_clock().toUtc()),
      dirty: const Value(true),
    );
    if (id == null) {
      await db.into(db.children).insert(values.copyWith(id: Value(childId)));
    } else {
      await (db.update(db.children)..where((c) => c.id.equals(id))).write(values);
    }
    return childId;
  }

  /// Soft-deletes the child and their measurements so the deletion syncs to other devices.
  Future<void> deleteChild(String id) => db.transaction(() async {
        final now = Value(_clock().toUtc());
        const tombstone = Value(true);
        await (db.update(db.measurements)..where((m) => m.childId.equals(id)))
            .write(MeasurementsCompanion(deleted: tombstone, dirty: tombstone, updatedAt: now));
        await (db.update(db.children)..where((c) => c.id.equals(id)))
            .write(ChildrenCompanion(deleted: tombstone, dirty: tombstone, updatedAt: now));
      });

  Future<String> addMeasurement({
    required String childId,
    required DateTime measuredOn,
    double? weightKg,
    double? heightCm,
    required String position,
    double? muacCm,
    String? notes,
  }) async {
    if (weightKg == null && heightCm == null) {
      throw ArgumentError('A measurement needs a weight or a length/height.');
    }
    final id = _uuid.v4();
    await db.into(db.measurements).insert(MeasurementsCompanion.insert(
          id: id,
          childId: childId,
          measuredOn: DateTime.utc(measuredOn.year, measuredOn.month, measuredOn.day),
          weightKg: Value(weightKg),
          heightCm: Value(heightCm),
          position: position,
          muacCm: Value(muacCm),
          notes: Value(_blankToNull(notes)),
          updatedAt: _clock().toUtc(),
        ));
    return id;
  }

  Future<void> deleteMeasurement(String id) =>
      (db.update(db.measurements)..where((m) => m.id.equals(id))).write(MeasurementsCompanion(
        deleted: const Value(true),
        dirty: const Value(true),
        updatedAt: Value(_clock().toUtc()),
      ));

  /// Number of local changes waiting to be uploaded.
  Stream<int> watchPendingCount() {
    final query = db.customSelect(
      'SELECT (SELECT COUNT(*) FROM children WHERE dirty = 1) + (SELECT COUNT(*) FROM measurements WHERE dirty = 1) AS n',
      readsFrom: {db.children, db.measurements},
    );
    return query.watchSingle().map((row) => row.read<int>('n'));
  }

  Stream<List<SyncConflict>> watchConflicts() =>
      (db.select(db.syncConflicts)..orderBy([(c) => OrderingTerm.asc(c.detectedAt)])).watch();

  static String? _blankToNull(String? value) => (value == null || value.trim().isEmpty) ? null : value.trim();
}
