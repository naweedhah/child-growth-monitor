import 'package:drift/drift.dart';

import '../data/database.dart';

/// Conversions between local rows and the field maps sent to the server. Sync bookkeeping
/// (`version`, `dirty`) never leaves the device; `deleted` does, as a tombstone.
class Records {
  static Map<String, Object?> childToRemote(Child c) => {
        'name': c.name,
        'sex': c.sex,
        'dateOfBirth': c.dateOfBirth.toUtc(),
        'guardianName': c.guardianName,
        'guardianPhone': c.guardianPhone,
        'area': c.area,
        'notes': c.notes,
        'updatedAt': c.updatedAt.toUtc(),
        'deleted': c.deleted,
      };

  static ChildrenCompanion childFromRemote(String id, Map<String, Object?> d, int version) => ChildrenCompanion(
        id: Value(id),
        name: Value(d['name']! as String),
        sex: Value(d['sex']! as String),
        dateOfBirth: Value(d['dateOfBirth']! as DateTime),
        guardianName: Value(d['guardianName']! as String),
        guardianPhone: Value(d['guardianPhone'] as String?),
        area: Value(d['area']! as String),
        notes: Value(d['notes'] as String?),
        updatedAt: Value(d['updatedAt']! as DateTime),
        deleted: Value(d['deleted'] as bool? ?? false),
        version: Value(version),
        dirty: const Value(false),
      );

  static Map<String, Object?> measurementToRemote(Measurement m) => {
        'childId': m.childId,
        'measuredOn': m.measuredOn.toUtc(),
        'weightKg': m.weightKg,
        'heightCm': m.heightCm,
        'position': m.position,
        'muacCm': m.muacCm,
        'notes': m.notes,
        'updatedAt': m.updatedAt.toUtc(),
        'deleted': m.deleted,
      };

  static MeasurementsCompanion measurementFromRemote(String id, Map<String, Object?> d, int version) =>
      MeasurementsCompanion(
        id: Value(id),
        childId: Value(d['childId']! as String),
        measuredOn: Value(d['measuredOn']! as DateTime),
        weightKg: Value((d['weightKg'] as num?)?.toDouble()),
        heightCm: Value((d['heightCm'] as num?)?.toDouble()),
        position: Value(d['position']! as String),
        muacCm: Value((d['muacCm'] as num?)?.toDouble()),
        notes: Value(d['notes'] as String?),
        updatedAt: Value(d['updatedAt']! as DateTime),
        deleted: Value(d['deleted'] as bool? ?? false),
        version: Value(version),
        dirty: const Value(false),
      );

  /// True when two field maps describe the same content (ignoring `updatedAt`), e.g. the same
  /// edit made on two phones. Such a "conflict" is resolved automatically.
  static bool sameContent(Map<String, Object?> a, Map<String, Object?> b) {
    final keys = {...a.keys, ...b.keys}..remove('updatedAt');
    return keys.every((k) => _normalise(a[k]) == _normalise(b[k]));
  }

  static Object? _normalise(Object? v) => switch (v) {
        DateTime d => d.toUtc().millisecondsSinceEpoch,
        num n => n.toDouble(),
        _ => v,
      };
}
