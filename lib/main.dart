import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'firebase_options.dart';

/// Emulator by default; build with `--dart-define=USE_FIREBASE_EMULATOR=false` for a real project.
const useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: true);

/// The Android emulator reaches the host computer at 10.0.2.2; a real phone needs the
/// computer's LAN IP via `--dart-define=EMULATOR_HOST=192.168.x.x`.
const emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: kIsWeb ? 'localhost' : '10.0.2.2',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // The local Drift database is the offline store, so Firestore's own cache is turned off:
  // pulls always read the server, and a sync attempt fails fast when offline.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);

  if (useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  }

  runApp(const ProviderScope(child: GrowthMonitorApp()));
}
