import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growth_monitor/data/database.dart';
import 'package:growth_monitor/data/repository.dart';
import 'package:growth_monitor/sync/firestore_remote_store.dart';
import 'package:growth_monitor/sync/remote_store.dart';
import 'package:growth_monitor/sync/sync_engine.dart';

/// One phone: its own database, repository and sync engine, all talking to [remote].
class Device {
  Device(RemoteStore remote, {required DateTime Function() clock})
      : db = AppDatabase(NativeDatabase.memory()) {
    repo = GrowthRepository(db, clock: clock);
    sync = SyncEngine(db, remote, clock: clock);
  }

  final AppDatabase db;
  late final GrowthRepository repo;
  late final SyncEngine sync;

  Future<Child> child(String id) => (db.select(db.children)..where((c) => c.id.equals(id))).getSingle();
  Future<List<SyncConflict>> conflicts() => db.select(db.syncConflicts).get();

  Future<String> registerChild({String name = 'Nethmi Perera'}) => repo.saveChild(
        name: name,
        sex: 'female',
        dateOfBirth: DateTime.utc(2025, 3, 1),
        guardianName: 'Kumari Perera',
        guardianPhone: '0771234567',
        area: 'Kaduwela',
      );

  Future<void> rename(String id, String name, {String area = 'Kaduwela'}) async {
    final c = await child(id);
    await repo.saveChild(
      id: id,
      name: name,
      sex: c.sex,
      dateOfBirth: c.dateOfBirth,
      guardianName: c.guardianName,
      guardianPhone: c.guardianPhone,
      area: area,
    );
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late Device phoneA;
  late Device phoneB;
  var now = DateTime.utc(2026, 11, 25, 8);
  DateTime clock() => now = now.add(const Duration(seconds: 1));

  setUp(() {
    firestore = FakeFirebaseFirestore();
    // The same health worker signed in on two phones.
    phoneA = Device(FirestoreRemoteStore(firestore, 'midwife-1'), clock: clock);
    phoneB = Device(FirestoreRemoteStore(firestore, 'midwife-1'), clock: clock);
  });

  tearDown(() async {
    await phoneA.db.close();
    await phoneB.db.close();
  });

  test('a child registered offline on one phone reaches the other phone', () async {
    final id = await phoneA.registerChild();
    await phoneA.repo.addMeasurement(childId: id, measuredOn: DateTime.utc(2026, 3, 1), weightKg: 8.1, heightCm: 70.2, position: 'lying');

    expect(await phoneA.sync.sync(), isA<SyncReport>().having((r) => r.pushed, 'pushed', 2));
    final report = await phoneB.sync.sync();

    expect(report.pulled, 2);
    final caseload = await phoneB.repo.loadCaseload();
    expect(caseload.single.child.name, 'Nethmi Perera');
    expect(caseload.single.latest!.weightKg, 8.1);
    expect((await phoneA.child(id)).dirty, isFalse);
    expect((await phoneA.child(id)).version, 1);
  });

  test('data is stored per health worker', () async {
    await phoneA.registerChild();
    await phoneA.sync.sync();

    final otherWorker = Device(FirestoreRemoteStore(firestore, 'midwife-2'), clock: clock);
    await otherWorker.sync.sync();
    expect(await otherWorker.repo.loadCaseload(), isEmpty);
    await otherWorker.db.close();
  });

  test('edits made offline on both phones become a conflict instead of a silent overwrite', () async {
    final id = await phoneA.registerChild();
    await phoneA.sync.sync();
    await phoneB.sync.sync();

    // Both phones edit the same child while offline.
    await phoneA.rename(id, 'Nethmi Perera', area: 'Malabe');
    await phoneB.rename(id, 'Nethmi Fernando');

    final first = await phoneA.sync.sync();
    final second = await phoneB.sync.sync();

    expect(first.conflicts, 0);
    expect(second.conflicts, 1);
    final conflict = (await phoneB.conflicts()).single;
    expect(conflict.entityId, id);
    expect(SyncEngine.decodeData(conflict.remoteJson)['area'], 'Malabe');
    // Phone B's edit is kept locally, still waiting to be uploaded.
    expect((await phoneB.child(id)).name, 'Nethmi Fernando');
    expect((await phoneB.child(id)).dirty, isTrue);
  });

  test('"keep mine" uploads the local version over the server copy', () async {
    final id = await phoneA.registerChild();
    await phoneA.sync.sync();
    await phoneB.sync.sync();
    await phoneA.rename(id, 'Version A');
    await phoneB.rename(id, 'Version B');
    await phoneA.sync.sync();
    await phoneB.sync.sync();

    await phoneB.sync.resolve((await phoneB.conflicts()).single, keepMine: true);
    await phoneB.sync.sync();
    await phoneA.sync.sync();

    expect(await phoneB.conflicts(), isEmpty);
    expect((await phoneA.child(id)).name, 'Version B');
    expect((await phoneA.child(id)).version, 3);
  });

  test('"keep theirs" replaces the local edit with the server copy', () async {
    final id = await phoneA.registerChild();
    await phoneA.sync.sync();
    await phoneB.sync.sync();
    await phoneA.rename(id, 'Version A');
    await phoneB.rename(id, 'Version B');
    await phoneA.sync.sync();
    await phoneB.sync.sync();

    await phoneB.sync.resolve((await phoneB.conflicts()).single, keepMine: false);

    final child = await phoneB.child(id);
    expect(child.name, 'Version A');
    expect(child.dirty, isFalse);
    expect((await phoneB.sync.sync()).pushed, 0);
  });

  test('the same edit on both phones resolves itself', () async {
    final id = await phoneA.registerChild();
    await phoneA.sync.sync();
    await phoneB.sync.sync();
    await phoneA.rename(id, 'Nethmi Silva');
    await phoneB.rename(id, 'Nethmi Silva');
    await phoneA.sync.sync();

    final report = await phoneB.sync.sync();

    expect(report.conflicts, 0);
    expect(await phoneB.conflicts(), isEmpty);
    expect((await phoneB.child(id)).dirty, isFalse);
  });

  test('a deletion syncs as a tombstone', () async {
    final id = await phoneA.registerChild();
    await phoneA.repo.addMeasurement(childId: id, measuredOn: DateTime.utc(2026, 3, 1), weightKg: 8.1, position: 'lying');
    await phoneA.sync.sync();
    await phoneB.sync.sync();
    expect(await phoneB.repo.loadCaseload(), hasLength(1));

    await phoneA.repo.deleteChild(id);
    await phoneA.sync.sync();
    await phoneB.sync.sync();

    expect(await phoneB.repo.loadCaseload(), isEmpty);
    expect((await phoneB.child(id)).deleted, isTrue);
  });

  test('an edit made while the upload is in flight stays dirty', () async {
    final db = AppDatabase(NativeDatabase.memory());
    late GrowthRepository repo;
    final remote = _EditDuringPush(() => repo);
    repo = GrowthRepository(db, clock: clock);
    final engine = SyncEngine(db, remote, clock: clock);
    final id = await repo.saveChild(name: 'Ayaan', sex: 'male', dateOfBirth: DateTime.utc(2025), guardianName: 'Riza', area: 'Kandy');
    remote.childId = id;

    await engine.sync();

    final child = await (db.select(db.children)..where((c) => c.id.equals(id))).getSingle();
    expect(child.name, 'Ayaan Mohamed');
    expect(child.version, 1);
    expect(child.dirty, isTrue, reason: 'the rename has not been uploaded yet');
    await db.close();
  });

  test('pull uses the server cursor and does not re-apply old records', () async {
    await phoneA.registerChild();
    await phoneA.sync.sync();
    expect((await phoneB.sync.sync()).pulled, 1);
    expect((await phoneB.sync.sync()).pulled, 0);
  });

  test('stored conflict data keeps dates intact', () {
    final data = {'dateOfBirth': DateTime.utc(2025, 3, 1), 'name': 'X', 'weightKg': 8.5, 'notes': null};
    final roundTrip = SyncEngine.decodeData(SyncEngine.encodeData(data));
    expect(roundTrip['dateOfBirth'], DateTime.utc(2025, 3, 1));
    expect(roundTrip['weightKg'], 8.5);
  });
}

/// A server that simulates the user editing the child on the phone while the upload is in flight.
class _EditDuringPush implements RemoteStore {
  _EditDuringPush(this.repo);

  final GrowthRepository Function() repo;
  String? childId;
  var _edited = false;

  @override
  Future<PushOutcome> push({required Entity entity, required String id, required int baseVersion, required Map<String, Object?> data}) async {
    if (!_edited && id == childId) {
      _edited = true;
      await repo().saveChild(id: id, name: 'Ayaan Mohamed', sex: 'male', dateOfBirth: DateTime.utc(2025), guardianName: 'Riza', area: 'Kandy');
    }
    return Accepted(baseVersion + 1);
  }

  @override
  Future<List<RemoteRecord>> pullSince(DateTime? cursor) async => const [];
}
