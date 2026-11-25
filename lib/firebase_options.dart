import 'package:firebase_core/firebase_core.dart';

/// Firebase configuration.
///
/// Out of the box the app talks to the **Firebase Local Emulator Suite** using a `demo-`
/// project id, which Firebase reserves for emulator-only use: no real project, keys or billing
/// are involved. To connect a real project, run `flutterfire configure` (it overwrites this file)
/// and build with `--dart-define=USE_FIREBASE_EMULATOR=false`.
class DefaultFirebaseOptions {
  static const projectId = 'demo-growth-monitor';

  static FirebaseOptions get currentPlatform => const FirebaseOptions(
        apiKey: 'demo-api-key',
        appId: '1:000000000000:android:0000000000000000',
        messagingSenderId: '000000000000',
        projectId: projectId,
      );
}
