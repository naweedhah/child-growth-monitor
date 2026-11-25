import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/repository.dart';
import 'growth/assessment.dart';
import 'growth/lms.dart';
import 'growth/who_standards.dart';
import 'sync/firestore_remote_store.dart';
import 'sync/sync_engine.dart';

// ---- Infrastructure (overridden in tests) -------------------------------------

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final authStateProvider = StreamProvider<User?>((ref) => ref.watch(firebaseAuthProvider).authStateChanges());

/// One local database per signed-in user, so two health workers sharing a phone never see each
/// other's caseload.
final databaseProvider = Provider<AppDatabase>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) throw StateError('No signed-in user');
  final db = AppDatabase(null, 'growth_monitor_$uid');
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<GrowthRepository>(
  (ref) => GrowthRepository(ref.watch(databaseProvider), clock: ref.watch(clockProvider)),
);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final uid = ref.watch(authStateProvider).value!.uid;
  return SyncEngine(
    ref.watch(databaseProvider),
    FirestoreRemoteStore(ref.watch(firestoreProvider), uid),
    clock: ref.watch(clockProvider),
  );
});

// ---- WHO standards ----------------------------------------------------------

final whoStandardsProvider = FutureProvider<WhoStandards>((ref) async {
  final files = await Future.wait([
    for (final name in ['weianthro', 'lenanthro', 'wflanthro', 'wfhanthro']) rootBundle.loadString('assets/who/$name.txt'),
  ]);
  return WhoStandards.fromTsv(wei: files[0], len: files[1], wfl: files[2], wfh: files[3]);
});

// ---- Caseload -----------------------------------------------------------------

/// A child plus their computed growth status.
class ChildStatus {
  const ChildStatus(this.record, this.latestZ, this.status);

  final ChildWithMeasurements record;
  final ZScores? latestZ;
  final NutritionStatus? status;

  Severity? get severity => status?.overall;
}

ZScores? zScoresFor(WhoStandards who, ChildWithMeasurements c, int index) {
  final m = c.measurements[index];
  final age = WhoStandards.ageInDays(c.child.dateOfBirth, m.measuredOn);
  if (age < 0 || age > WhoStandards.maxAgeDays) return null;
  return who.compute(
    sex: c.child.sex == 'male' ? Sex.male : Sex.female,
    ageDays: age,
    weightKg: m.weightKg,
    heightCm: m.heightCm,
    position: m.position == 'standing' ? MeasuredPosition.standing : MeasuredPosition.lying,
  );
}

ChildStatus assess(WhoStandards who, ChildWithMeasurements c) {
  final n = c.measurements.length;
  if (n == 0) return ChildStatus(c, null, null);
  final latest = zScoresFor(who, c, n - 1);
  final previous = n > 1 ? zScoresFor(who, c, n - 2) : null;
  return ChildStatus(c, latest, latest == null ? null : NutritionStatus.from(latest, previous: previous));
}

final caseloadProvider = StreamProvider<List<ChildStatus>>((ref) async* {
  final who = await ref.watch(whoStandardsProvider.future);
  await for (final caseload in ref.watch(repositoryProvider).watchCaseload()) {
    final assessed = caseload.map((c) => assess(who, c)).toList()
      // Most urgent first, then alphabetical.
      ..sort((a, b) {
        final bySeverity = (b.severity?.index ?? -1).compareTo(a.severity?.index ?? -1);
        return bySeverity != 0 ? bySeverity : a.record.child.name.compareTo(b.record.child.name);
      });
    yield assessed;
  }
});

final childProvider = Provider.family<AsyncValue<ChildStatus?>, String>(
  (ref, id) => ref.watch(caseloadProvider).whenData((all) => all.where((c) => c.record.child.id == id).firstOrNull),
);

final pendingChangesProvider = StreamProvider<int>((ref) => ref.watch(repositoryProvider).watchPendingCount());
final conflictsProvider = StreamProvider<List<SyncConflict>>((ref) => ref.watch(repositoryProvider).watchConflicts());

// ---- Sync -----------------------------------------------------------------------

enum SyncPhase { idle, syncing, offline, error }

class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.lastSyncedAt, this.message});

  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? message;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSyncedAt, String? message}) =>
      SyncStatus(phase: phase ?? this.phase, lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt, message: message);
}

/// Runs sync when the app starts, when the phone comes back online, shortly after local edits,
/// and when the user asks. Only one sync runs at a time.
class SyncController extends Notifier<SyncStatus> {
  Timer? _debounce;
  Future<void>? _running;

  @override
  SyncStatus build() {
    final connectivity = ref.watch(connectivityProvider);
    final sub = connectivity.onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(syncNow());
      } else {
        state = state.copyWith(phase: SyncPhase.offline);
      }
    });
    // Upload a few seconds after the last local edit, batching quick successive changes.
    ref.listen(pendingChangesProvider, (_, next) {
      if ((next.value ?? 0) > 0) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 3), () => unawaited(syncNow()));
      }
    });
    ref.onDispose(() {
      sub.cancel();
      _debounce?.cancel();
    });
    Future.microtask(syncNow);
    return const SyncStatus();
  }

  Future<void> syncNow() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    final online = (await ref.read(connectivityProvider).checkConnectivity()).any((r) => r != ConnectivityResult.none);
    if (!online) {
      state = state.copyWith(phase: SyncPhase.offline);
      return;
    }
    state = state.copyWith(phase: SyncPhase.syncing);
    try {
      final report = await ref.read(syncEngineProvider).sync();
      state = SyncStatus(
        phase: SyncPhase.idle,
        lastSyncedAt: ref.read(clockProvider)(),
        message: report.conflicts > 0 ? '${report.conflicts} change(s) need your review' : null,
      );
    } on FirebaseException catch (e) {
      final offline = e.code == 'unavailable' || e.code == 'deadline-exceeded';
      state = state.copyWith(phase: offline ? SyncPhase.offline : SyncPhase.error, message: offline ? null : e.message);
    } catch (e) {
      state = state.copyWith(phase: SyncPhase.error, message: '$e');
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
