import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Columns every synced record carries.
///
/// * [version] is the server version this copy is based on (0 = never uploaded). The sync
///   engine uses it for optimistic concurrency: an upload only succeeds if the server is still
///   at this version, otherwise someone else changed the record and it becomes a conflict.
/// * [dirty] marks local changes that have not been uploaded yet.
/// * [deleted] is a tombstone, so deletions sync to other devices instead of silently vanishing.
mixin SyncColumns on Table {
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
}

@DataClassName('Child')
class Children extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 2, max: 80)();
  TextColumn get sex => text().check(sex.isIn(['male', 'female']))();
  DateTimeColumn get dateOfBirth => dateTime()();
  TextColumn get guardianName => text().withLength(min: 2, max: 80)();
  TextColumn get guardianPhone => text().nullable()();

  /// Village or Grama Niladhari division, used to group a midwife's caseload.
  TextColumn get area => text().withLength(min: 2, max: 80)();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Measurement')
class Measurements extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get childId => text().references(Children, #id)();
  DateTimeColumn get measuredOn => dateTime()();
  RealColumn get weightKg => real().nullable()();
  RealColumn get heightCm => real().nullable()();
  TextColumn get position => text().check(position.isIn(['lying', 'standing']))();

  /// Mid-upper arm circumference, a quick wasting screen used alongside weight-for-height.
  RealColumn get muacCm => real().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (weight_kg IS NOT NULL OR height_cm IS NOT NULL)'];
}

/// A record that changed both here and on the server since the last sync. The midwife decides
/// which version to keep; nothing is overwritten silently.
@DataClassName('SyncConflict')
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()(); // 'child' | 'measurement'
  TextColumn get entityId => text()();
  TextColumn get remoteJson => text()();
  IntColumn get remoteVersion => integer()();
  DateTimeColumn get detectedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {entity, entityId},
      ];
}

/// Small key/value store for sync bookkeeping (e.g. the pull cursor).
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Children, Measurements, SyncConflicts, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor, String name = 'growth_monitor']) : super(executor ?? driftDatabase(name: name));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
        onCreate: (m) async {
          await m.createAll();
          await m.createIndex(Index('measurements_child', 'CREATE INDEX measurements_child ON measurements (child_id, measured_on)'));
          await m.createIndex(Index('children_dirty', 'CREATE INDEX children_dirty ON children (dirty)'));
        },
      );
}
