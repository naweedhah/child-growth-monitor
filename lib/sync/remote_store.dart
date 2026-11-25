/// The server side of sync, kept abstract so the engine can be tested without a network and the
/// backend could be swapped (Firestore today).
enum Entity {
  child('children'),
  measurement('measurements');

  const Entity(this.collection);
  final String collection;
}

/// A record as stored on the server.
class RemoteRecord {
  const RemoteRecord({
    required this.entity,
    required this.id,
    required this.version,
    required this.data,
    required this.serverUpdatedAt,
  });

  final Entity entity;
  final String id;

  /// Incremented by the server on every accepted write.
  final int version;

  /// Field values (dates as [DateTime]), including `deleted`.
  final Map<String, Object?> data;
  final DateTime serverUpdatedAt;
}

sealed class PushOutcome {
  const PushOutcome();
}

/// The server was still at the version we based our change on; it now holds our data.
class Accepted extends PushOutcome {
  const Accepted(this.newVersion);
  final int newVersion;
}

/// Someone else changed the record first. Nothing was written.
class Rejected extends PushOutcome {
  const Rejected(this.current);
  final RemoteRecord current;
}

abstract interface class RemoteStore {
  /// Writes [data] only if the server copy is still at [baseVersion] (0 = must not exist yet).
  /// This check-and-write is atomic, so two devices can never both "win".
  Future<PushOutcome> push({
    required Entity entity,
    required String id,
    required int baseVersion,
    required Map<String, Object?> data,
  });

  /// Everything changed on the server at or after [cursor] (all records when null), oldest first.
  Future<List<RemoteRecord>> pullSince(DateTime? cursor);
}
