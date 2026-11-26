import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase configuration.
///
/// Out of the box the app talks to the **Firebase Local Emulator Suite** using a `demo-`
/// project id, which Firebase reserves for emulator-only use: no real project, keys or billing
/// are involved. To connect a real project, run `flutterfire configure` (it overwrites this file)
/// and build with `--dart-define=USE_FIREBASE_EMULATOR=false`.
class DefaultFirebaseOptions {
  static const projectId = 'demo-growth-monitor';

  static FirebaseOptions get currentPlatform => FirebaseOptions(
        // Placeholders shaped like real values: the iOS SDK refuses to start with an API key
        // that is not 39 characters starting with `A`, or an app id whose platform segment is
        // not `ios`. The emulators never check either.
        apiKey: 'AIzaDemoKeyForLocalEmulatorOnly00000000',
        appId: '1:000000000000:${_platformSegment()}:0000000000000000',
        messagingSenderId: '000000000000',
        projectId: projectId,
      );

  static String _platformSegment() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
      _ => 'android',
    };
  }
}
