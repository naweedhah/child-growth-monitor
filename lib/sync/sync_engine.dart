import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database.dart';
import 'records.dart';
import 'remote_store.dart';

class SyncReport {
  const SyncReport({this.pushed = 0, this.pulled = 0, this.conflicts = 0});

  final int pushed;
  final int pulled;
  final int conflicts;

  @override
  String toString() => 'SyncReport(pushed: $pushed, pulled: $pulled, conflicts: $conflicts)';
}

/// Two-way sync between the local Drift database and a [RemoteStore].
///
/// 1. **Push** every dirty record with the server version it was based on. The server accepts
///    it only if nobody else wrote in between (optimistic concurrency); otherwise the record
///    becomes a [SyncConflict] for the health worker to resolve.
/// 2. **Pull** everything the server changed since the last cursor. Clean local copies are
///    updated; a dirty local copy with a newer server version also becomes a conflict.
///
/// Records with an open conflict are left alone until it is resolved, so neither side's
/// edits are lost.
class SyncEngine {
  SyncEngine(this.db, this.remote, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final RemoteStore remote;
  final DateTime Function() _clock;

  static const _cursorKey = 'pullCursor';

  Future<SyncReport> sync() async {
    final pushed = await _push();
    final (pulled, pullConflicts) = await _pull();
    return SyncReport(pushed: pushed.$1, pulled: pulled, conflicts: pushed.$2 + pullConflicts);
  }

  // ---- Push -----------------------------------------------------------------

  Future<(int pushed, int conflicts)> _push() async {
    final blocked = await _entitiesWithConflicts();
    var pushed = 0;
    var conflicts = 0;

    // Children before measurements, so the server never has an orphan measurement.
    final children = await (db.select(db.children)..where((c) => c.dirty.equals(true))).get();
    for (final child in children) {
      if (blocked.contains((Entity.child, child.id))) continue;
      final data = Records.childToRemote(child);
      switch (await remote.push(entity: Entity.child, id: child.id, baseVersion: child.version, data: data)) {
        case Accepted(:final newVersion):
          await _markClean(db.children, child.id, child.updatedAt, newVersion);
          pushed++;
        case Rejected(:final current):
          if (await _autoResolve(current, data)) continue;
          await _recordConflict(current);
          conflicts++;
      }
    }

    final measurements = await (db.select(db.measurements)..where((m) => m.dirty.equals(true))).get();
    for (final m in measurements) {
      if (blocked.contains((Entity.measurement, m.id))) continue;
      final data = Records.measurementToRemote(m);
      switch (await remote.push(entity: Entity.measurement, id: m.id, baseVersion: m.version, data: data)) {
        case Accepted(:final newVersion):
          await _markClean(db.measurements, m.id, m.updatedAt, newVersion);
          pushed++;
        case Rejected(:final current):
          if (await _autoResolve(current, data)) continue;
          await _recordConflict(current);
          conflicts++;
      }
    }
    return (pushed, conflicts);
  }

  /// Clears `dirty` only if the row wasn't edited again while the upload was in flight.
  Future<void> _markClean<T extends Table, R>(TableInfo<T, R> table, String id, DateTime pushedUpdatedAt, int version) =>
      db.customUpdate(
        'UPDATE ${table.actualTableName} SET version = ?, dirty = CASE WHEN updated_at = ? THEN 0 ELSE dirty END WHERE id = ?',
        variables: [Variable.withInt(version), Variable.withDateTime(pushedUpdatedAt), Variable.withString(id)],
        updates: {table},
      );

  /// The same change was made on both sides: adopt the server version and move on.
  Future<bool> _autoResolve(RemoteRecord current, Map<String, Object?> local) async {
    if (!Records.sameContent(current.data, local)) return false;
    await _applyRemote(current);
    return true;
  }

  // ---- Pull -----------------------------------------------------------------

  Future<(int pulled, int conflicts)> _pull() async {
    final cursorRow = await (db.select(db.syncMeta)..where((m) => m.key.equals(_cursorKey))).getSingleOrNull();
    final cursor = cursorRow == null ? null : DateTime.parse(cursorRow.value);
    final records = await remote.pullSince(cursor);
    final blocked = await _entitiesWithConflicts();

    var pulled = 0;
    var conflicts = 0;
    var newest = cursor;

    await db.transaction(() async {
      for (final record in records) {
        if (newest == null || record.serverUpdatedAt.isAfter(newest!)) newest = record.serverUpdatedAt;

        final local = await _localState(record.entity, record.id);
        if (local != null && record.version <= local.version) continue; // already have it (often our own push)
        if (blocked.contains((record.entity, record.id))) {
          await _recordConflict(record); // keep the open conflict pointing at the latest server copy
          continue;
        }
        if (local != null && local.dirty) {
          await _recordConflict(record);
          conflicts++;
          continue;
        }
        await _applyRemote(record);
        pulled++;
      }
      if (newest != null) {
        await db.into(db.syncMeta).insertOnConflictUpdate(SyncMetaData(key: _cursorKey, value: newest!.toIso8601String()));
      }
    });
    return (pulled, conflicts);
  }

  Future<({int version, bool dirty})?> _localState(Entity entity, String id) async {
    switch (entity) {
      case Entity.child:
        final row = await (db.select(db.children)..where((c) => c.id.equals(id))).getSingleOrNull();
        return row == null ? null : (version: row.version, dirty: row.dirty);
      case Entity.measurement:
        final row = await (db.select(db.measurements)..where((m) => m.id.equals(id))).getSingleOrNull();
        return row == null ? null : (version: row.version, dirty: row.dirty);
    }
  }

  Future<void> _applyRemote(RemoteRecord record) async {
    switch (record.entity) {
      case Entity.child:
        await db.into(db.children).insertOnConflictUpdate(Records.childFromRemote(record.id, record.data, record.version));
      case Entity.measurement:
        await db
            .into(db.measurements)
            .insertOnConflictUpdate(Records.measurementFromRemote(record.id, record.data, record.version));
    }
  }

  // ---- Conflicts --------------------------------------------------------------

  Future<Set<(Entity, String)>> _entitiesWithConflicts() async {
    final rows = await db.select(db.syncConflicts).get();
    return {for (final r in rows) (Entity.values.byName(r.entity), r.entityId)};
  }

  Future<void> _recordConflict(RemoteRecord current) => db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          entity: current.entity.name,
          entityId: current.id,
          remoteJson: encodeData(current.data),
          remoteVersion: current.version,
          detectedAt: _clock().toUtc(),
        ),
        onConflict: DoUpdate.withExcluded(
          (old, excluded) => SyncConflictsCompanion.custom(remoteJson: excluded.remoteJson, remoteVersion: excluded.remoteVersion),
          target: [db.syncConflicts.entity, db.syncConflicts.entityId],
        ),
      );

  /// Resolves a conflict. Keeping mine rebases the local edit on the server version so the next
  /// push overwrites it; keeping theirs replaces the local copy with the server's.
  Future<void> resolve(SyncConflict conflict, {required bool keepMine}) => db.transaction(() async {
        final entity = Entity.values.byName(conflict.entity);
        if (keepMine) {
          final TableInfo table = entity == Entity.child ? db.children : db.measurements;
          await db.customUpdate(
            'UPDATE ${table.actualTableName} SET version = ?, dirty = 1 WHERE id = ?',
            variables: [Variable.withInt(conflict.remoteVersion), Variable.withString(conflict.entityId)],
            updates: {table},
          );
        } else {
          await _applyRemote(RemoteRecord(
            entity: entity,
            id: conflict.entityId,
            version: conflict.remoteVersion,
            data: decodeData(conflict.remoteJson),
            serverUpdatedAt: _clock().toUtc(),
          ));
        }
        await (db.delete(db.syncConflicts)..where((c) => c.id.equals(conflict.id))).go();
      });

  // ---- JSON for stored conflicts (DateTime-safe) ---------------------------------

  static String encodeData(Map<String, Object?> data) =>
      jsonEncode(data, toEncodable: (v) => v is DateTime ? {r'$date': v.toUtc().toIso8601String()} : v);

  static Map<String, Object?> decodeData(String json) => (jsonDecode(json) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v is Map && v.containsKey(r'$date') ? DateTime.parse(v[r'$date'] as String) : v),
      );
}
