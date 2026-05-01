import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/transcription/presentation/screens/transcription_screen.dart';

/// Application routes.
///
/// Single screen today — but we still use go_router so that adding new
/// features (auth, history, settings) is a one-line route addition rather
/// than a refactor.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const TranscriptionScreen(),
      ),
    ],
  );
});

class AppRoutes {
  AppRoutes._();
  static const home = '/';
  static const homeName = 'home';
}
