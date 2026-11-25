// Renders the README screenshots from the real widgets with demo data, without a device:
//   flutter test tool/screenshots_test.dart --update-goldens
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growth_monitor/data/database.dart';
import 'package:growth_monitor/sync/sync_engine.dart';
import 'package:material_ui/material_ui.dart';

import '../test/app_test.dart' show Harness, settle, finish;

Future<void> loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter'}/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async => ByteData.sublistView(File('$dir/$f').readAsBytesSync());
  await (FontLoader('Roboto')
        ..addFont(read('Roboto-Regular.ttf'))
        ..addFont(read('Roboto-Medium.ttf'))
        ..addFont(read('Roboto-Bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'))).load();
}

/// A caseload with a mix of statuses and a few months of visits each.
Future<String> seed(Harness h) async {
  // Visits are given by the child's age in months at the visit.
  Future<String> child(String name, String sex, DateTime dob, String area, List<(int ageMonths, double kg, double cm)> visits) async {
    final id = await h.repo.saveChild(name: name, sex: sex, dateOfBirth: dob, guardianName: 'Guardian of $name', guardianPhone: '0771234567', area: area);
    for (final (age, kg, cm) in visits) {
      await h.repo.addMeasurement(
        childId: id,
        measuredOn: DateTime(dob.year, dob.month + age, dob.day),
        weightKg: kg,
        heightCm: cm,
        position: age < 24 ? 'lying' : 'standing',
      );
    }
    return id;
  }

  final featured = await child('Nethmi Perera', 'female', DateTime(2025, 6, 10), 'Kaduwela', [
    (0, 3.2, 49.0), (2, 5.0, 56.5), (4, 6.2, 61.0), (6, 7.1, 64.5), (9, 7.9, 69.0), (12, 8.4, 72.0), (15, 8.3, 74.0), (17, 7.8, 74.6),
  ]);
  await child('Binu Fernando', 'male', DateTime(2024, 8, 2), 'Malabe', [(23, 9.0, 80.0), (27, 8.6, 81.5)]);
  await child('Amaya Silva', 'female', DateTime(2025, 1, 20), 'Kaduwela', [(19, 8.9, 77.0), (22, 9.3, 79.0)]);
  await child('Kavindu Jayasuriya', 'male', DateTime(2023, 12, 5), 'Athurugiriya', [(30, 12.4, 89.0), (35, 13.6, 93.5)]);
  await child('Sahan Bandara', 'male', DateTime(2025, 9, 1), 'Malabe', []);
  return featured;
}

Future<void> shoot(WidgetTester tester, String name) async {
  await settle(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/screenshots/$name.png'));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(loadFonts);

  void phone(WidgetTester tester) {
    // flutter_test draws shadows as black outlines by default; screenshots want real shadows.
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('caseload, profile, visit', (tester) async {
    phone(tester);
    final h = Harness(online: false);
    late String id;
    await tester.runAsync(() async => id = await seed(h));
    await tester.pumpWidget(h.app());
    await shoot(tester, 'caseload');

    await tester.tap(find.text('Nethmi Perera'));
    await shoot(tester, 'profile');

    await tester.tap(find.text('Record visit'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '8.0');
    await tester.enterText(find.widgetWithText(TextFormField, 'Length / height'), '75.8');
    await tester.enterText(find.widgetWithText(TextFormField, 'MUAC (optional)'), '12.1');
    await tester.pump();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -260));
    await shoot(tester, 'visit');
    expect(id, isNotEmpty);
    await finish(tester, h);
    debugDisableShadows = true;
  });

  testWidgets('sync conflict', (tester) async {
    phone(tester);
    final h = Harness(online: false);
    await tester.runAsync(() async {
      final id = await seed(h);
      await h.db.into(h.db.syncConflicts).insert(SyncConflictsCompanion.insert(
            entity: 'child',
            entityId: id,
            remoteJson: SyncEngine.encodeData({
              'name': 'Nethmi Perera',
              'sex': 'female',
              'dateOfBirth': DateTime.utc(2025, 6, 10),
              'guardianName': 'Guardian of Nethmi Perera',
              'guardianPhone': '0719876543',
              'area': 'Malabe',
              'notes': null,
              'updatedAt': DateTime.utc(2026, 11, 24),
              'deleted': false,
            }),
            remoteVersion: 3,
            detectedAt: DateTime.utc(2026, 11, 25),
          ));
    });
    await tester.pumpWidget(h.app());
    await settle(tester);
    await tester.tap(find.byType(IconButton).first);
    await shoot(tester, 'sync');
    await finish(tester, h);
    debugDisableShadows = true;
  });
}
