import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growth_monitor/app.dart';
import 'package:growth_monitor/data/database.dart';
import 'package:growth_monitor/data/repository.dart';
import 'package:growth_monitor/providers.dart';

import 'who_standards_test.dart' show loadStandards;
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class MockConnectivity extends Mock implements Connectivity {}

final today = DateTime(2026, 11, 25);

/// Loaded once from disk: rootBundle caches futures across tests, which breaks under fake async.
final who = loadStandards();

class Harness {
  Harness({bool signedIn = true, bool online = true})
      : db = AppDatabase(NativeDatabase.memory()),
        auth = MockFirebaseAuth(signedIn: signedIn, mockUser: MockUser(uid: 'midwife-1', email: 'midwife@example.lk')),
        firestore = FakeFirebaseFirestore(),
        connectivity = MockConnectivity() {
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [online ? ConnectivityResult.wifi : ConnectivityResult.none]);
    when(() => connectivity.onConnectivityChanged).thenAnswer((_) => const Stream.empty());
    repo = GrowthRepository(db, clock: () => today);
  }

  final AppDatabase db;
  final MockFirebaseAuth auth;
  final FakeFirebaseFirestore firestore;
  final MockConnectivity connectivity;
  late final GrowthRepository repo;

  Widget app() => ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          connectivityProvider.overrideWithValue(connectivity),
          clockProvider.overrideWithValue(() => today),
          databaseProvider.overrideWithValue(db),
          whoStandardsProvider.overrideWith((ref) async => who),
        ],
        child: const GrowthMonitorApp(),
      );

  Future<String> addChild(String name, {String sex = 'female', DateTime? dob}) => repo.saveChild(
        name: name,
        sex: sex,
        dateOfBirth: dob ?? DateTime(2025, 11, 25),
        guardianName: 'Kumari Perera',
        area: 'Kaduwela',
      );
}

/// Drift streams and Firestore fakes do real async work, so let it run between frames.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> finish(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 4)); // let the sync debounce expire
  await tester.runAsync(h.db.close);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('signed-out users see sign-in, and form errors appear before calling Firebase', (tester) async {
    usePhoneScreen(tester);
    final h = Harness(signedIn: false);
    await tester.pumpWidget(h.app());
    await settle(tester);

    expect(find.text('Child Growth Monitor'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email.'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters.'), findsOneWidget);
    await finish(tester, h);
  });

  testWidgets('the caseload lists the most urgent children first', (tester) async {
    usePhoneScreen(tester);
    final h = Harness();
    await tester.runAsync(() async {
      final healthy = await h.addChild('Amaya Silva');
      await h.repo.addMeasurement(childId: healthy, measuredOn: today, weightKg: 9.0, heightCm: 74.0, position: 'lying');
      final wasted = await h.addChild('Binu Perera', sex: 'male');
      // 12-month-old boy, 6.4 kg at 75 cm: severely wasted and underweight.
      await h.repo.addMeasurement(childId: wasted, measuredOn: today, weightKg: 6.4, heightCm: 75.0, position: 'lying');
      await h.addChild('Chamod Fernando', sex: 'male');
    });

    await tester.pumpWidget(h.app());
    await settle(tester);

    final names = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title! as Text).data).toList();
    expect(names, ['Binu Perera', 'Amaya Silva', 'Chamod Fernando']);
    expect(find.text('Severe'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('No measurements'), findsOneWidget);

    await tester.tap(find.text('Needs attention'));
    await tester.pump();
    expect(find.text('Amaya Silva'), findsNothing);
    expect(find.text('Binu Perera'), findsOneWidget);

    await tester.ensureVisible(find.text('Overdue visit'));
    await tester.tap(find.text('Overdue visit'));
    await tester.pump();
    expect(find.text('Chamod Fernando'), findsOneWidget, reason: 'never measured counts as overdue');
    expect(find.text('Binu Perera'), findsNothing);
    await finish(tester, h);
  });

  testWidgets('recording a visit previews z-scores live and updates the profile', (tester) async {
    usePhoneScreen(tester);
    final h = Harness();
    late String id;
    await tester.runAsync(() async => id = await h.addChild('Nethmi Perera'));
    await tester.pumpWidget(h.app());
    await settle(tester);

    await tester.tap(find.text('Nethmi Perera'));
    await settle(tester);
    expect(find.textContaining('No measurements yet'), findsOneWidget);

    await tester.tap(find.text('Record visit'));
    await settle(tester);
    // A 12-month-old girl on about WHO's -2 SD lines for weight and length.
    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '7.0');
    await tester.enterText(find.widgetWithText(TextFormField, 'Length / height'), '68.9');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('zPreview')),
      200,
      scrollable: find.descendant(of: find.byType(Form), matching: find.byType(Scrollable)).first,
    );

    expect(find.byKey(const Key('zPreview')), findsOneWidget);
    expect(find.textContaining('WAZ -2.1'), findsOneWidget);
    expect(find.textContaining('HAZ -2.0'), findsOneWidget);
    expect(find.text('• Underweight'), findsOneWidget);

    await tester.ensureVisible(find.text('Save visit'));
    await tester.tap(find.text('Save visit'));
    await settle(tester);

    // Back on the profile: the z-score cards and the finding.
    expect(find.text('-2.1'), findsOneWidget);
    expect(find.text('Underweight'), findsOneWidget);
    final saved = await tester.runAsync(() => h.repo.loadCaseload());
    expect(saved!.single.measurements.single.weightKg, 7.0);
    expect(saved.single.child.id, id);
    await finish(tester, h);
  });

  testWidgets('implausible values must be confirmed before saving', (tester) async {
    usePhoneScreen(tester);
    final h = Harness();
    await tester.runAsync(() => h.addChild('Ishara Bandara'));
    await tester.pumpWidget(h.app());
    await settle(tester);
    await tester.tap(find.text('Ishara Bandara'));
    await settle(tester);
    await tester.tap(find.text('Record visit'));
    await settle(tester);

    // 30 kg for a 1-year-old: a typo for 3.0 or 13.0.
    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '30');
    await tester.pump();
    await tester.ensureVisible(find.text('Save visit'));
    await tester.tap(find.text('Save visit'));
    await tester.pumpAndSettle();

    expect(find.text('Please re-check this measurement'), findsOneWidget);
    await tester.tap(find.text('Fix it'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() => h.repo.loadCaseload());
    expect(saved!.single.measurements, isEmpty);
    await finish(tester, h);
  });

  testWidgets('out-of-range numbers show inline errors', (tester) async {
    usePhoneScreen(tester);
    final h = Harness();
    await tester.runAsync(() => h.addChild('Ishara Bandara'));
    await tester.pumpWidget(h.app());
    await settle(tester);
    await tester.tap(find.text('Ishara Bandara'));
    await settle(tester);
    await tester.tap(find.text('Record visit'));
    await settle(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '75');
    await tester.enterText(find.widgetWithText(TextFormField, 'Length / height'), 'abc');
    await tester.pump();

    expect(find.text('Weight must be between 0.5 and 40.0 kg.'), findsOneWidget);
    expect(find.text('Length/height must be a number.'), findsOneWidget);
    await finish(tester, h);
  });

  testWidgets('changes made offline wait on the phone and the sync screen says so', (tester) async {
    usePhoneScreen(tester);
    final h = Harness(online: false);
    await tester.runAsync(() => h.addChild('Sahan Jayasuriya', sex: 'male'));
    await tester.pumpWidget(h.app());
    await settle(tester);

    expect(find.textContaining('Offline. Everything you record is saved on this phone'), findsOneWidget);
    await tester.tap(find.byTooltip('Offline: 1 change(s) saved on this phone'));
    await settle(tester);
    expect(find.text('1 change(s) on this phone not uploaded yet'), findsOneWidget);

    final remote = await tester.runAsync(() => h.firestore.collection('users/midwife-1/children').get());
    expect(remote!.docs, isEmpty);
    await finish(tester, h);
  });

  testWidgets('when online, local changes are uploaded to Firestore', (tester) async {
    usePhoneScreen(tester);
    final h = Harness();
    await tester.runAsync(() => h.addChild('Sahan Jayasuriya', sex: 'male'));
    await tester.pumpWidget(h.app());
    await settle(tester);

    final remote = await tester.runAsync(() => h.firestore.collection('users/midwife-1/children').get());
    expect(remote!.docs.single.data()['name'], 'Sahan Jayasuriya');
    expect(remote.docs.single.data()['version'], 1);
    expect(find.byTooltip('All changes synced'), findsOneWidget);
    await finish(tester, h);
  });
}
