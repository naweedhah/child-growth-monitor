import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'providers.dart';
import 'ui/caseload_screen.dart';
import 'ui/child_form_screen.dart';
import 'ui/child_screen.dart';
import 'ui/measurement_form_screen.dart';
import 'ui/sign_in_screen.dart';
import 'ui/sync_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier<bool?>(null);
  ref.listen(authStateProvider, (_, next) => signedIn.value = next.value != null, fireImmediately: true);
  ref.onDispose(signedIn.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: signedIn,
    redirect: (context, state) {
      if (signedIn.value == null) return null; // still restoring the session
      final atSignIn = state.matchedLocation == '/sign-in';
      if (signedIn.value == false) return atSignIn ? null : '/sign-in';
      return atSignIn ? '/' : null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/', builder: (_, _) => const CaseloadScreen()),
      GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
      GoRoute(path: '/children/new', builder: (_, _) => const ChildFormScreen()),
      GoRoute(path: '/children/:id', builder: (_, s) => ChildScreen(childId: s.pathParameters['id']!)),
      GoRoute(path: '/children/:id/edit', builder: (_, s) => ChildFormScreen(childId: s.pathParameters['id']!)),
      GoRoute(path: '/children/:id/measure', builder: (_, s) => MeasurementFormScreen(childId: s.pathParameters['id']!)),
    ],
  );
});

class GrowthMonitorApp extends ConsumerWidget {
  const GrowthMonitorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authStateProvider).value != null;
    // Start background sync only while someone is signed in.
    if (signedIn) ref.watch(syncControllerProvider);

    const seed = Color(0xFF00796B);
    return MaterialApp.router(
      title: 'Child Growth Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
