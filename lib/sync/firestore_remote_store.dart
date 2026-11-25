import 'package:cloud_firestore/cloud_firestore.dart';

import 'remote_store.dart';

/// [RemoteStore] on Cloud Firestore.
///
/// Data lives under `users/{uid}/children` and `users/{uid}/measurements`; the security rules in
/// `firestore.rules` only let a signed-in health worker read and write their own caseload.
/// Each document carries `version` and a server-assigned `serverUpdatedAt`, which is what the
/// pull cursor uses (device clocks are never trusted for ordering).
class FirestoreRemoteStore implements RemoteStore {
  FirestoreRemoteStore(this._firestore, this._uid);

  final FirebaseFirestore _firestore;
  final String _uid;

  CollectionReference<Map<String, dynamic>> _collection(Entity entity) =>
      _firestore.collection('users').doc(_uid).collection(entity.collection);

  @override
  Future<PushOutcome> push({
    required Entity entity,
    required String id,
    required int baseVersion,
    required Map<String, Object?> data,
  }) {
    final ref = _collection(entity).doc(id);
    return _firestore.runTransaction<PushOutcome>((tx) async {
      final snapshot = await tx.get(ref);
      final serverVersion = snapshot.exists ? (snapshot.data()!['version'] as num).toInt() : 0;

      if (serverVersion != baseVersion) {
        return Rejected(_toRecord(entity, snapshot));
      }

      tx.set(ref, {
        for (final e in data.entries) e.key: _toFirestore(e.value),
        'version': baseVersion + 1,
        'serverUpdatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _uid,
      });
      return Accepted(baseVersion + 1);
    });
  }

  @override
  Future<List<RemoteRecord>> pullSince(DateTime? cursor) async {
    final records = <RemoteRecord>[];
    // Children first, so a pulled measurement never arrives before the child it belongs to.
    for (final entity in Entity.values) {
      Query<Map<String, dynamic>> query = _collection(entity).orderBy('serverUpdatedAt');
      if (cursor != null) {
        // >= rather than >: two writes can share a timestamp tick. Records we already have are
        // skipped by the engine's version check, so re-reading the boundary is harmless.
        query = query.where('serverUpdatedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cursor));
      }
      final page = await query.get();
      records.addAll(page.docs.map((doc) => _toRecord(entity, doc)));
    }
    return records;
  }

  RemoteRecord _toRecord(Entity entity, DocumentSnapshot<Map<String, dynamic>> doc) {
    final raw = doc.data() ?? const <String, dynamic>{};
    return RemoteRecord(
      entity: entity,
      id: doc.id,
      version: (raw['version'] as num?)?.toInt() ?? 0,
      data: {
        for (final e in raw.entries)
          if (!const {'version', 'serverUpdatedAt', 'updatedBy'}.contains(e.key)) e.key: _fromFirestore(e.value),
      },
      serverUpdatedAt: (raw['serverUpdatedAt'] as Timestamp?)?.toDate().toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static Object? _toFirestore(Object? value) => value is DateTime ? Timestamp.fromDate(value) : value;

  static Object? _fromFirestore(Object? value) => value is Timestamp ? value.toDate().toUtc() : value;
}
