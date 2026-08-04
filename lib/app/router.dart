import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/transcription/presentation/screens/transcription_screen.dart';

/// Listenable bridge to trigger GoRouter redirects when AuthState updates.
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) {
      notifyListeners();
    });
  }
}

/// Application routes with authentication guards.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = RouterRefreshNotifier(ref);

  return GoRouter(
    refreshListenable: refreshNotifier,
    initialLocation: AppRoutes.login,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      if (authState.isInitializing) {
        return null;
      }

      final isAuth = authState.isAuthenticated;
      final isLoggingIn = state.matchedLocation == AppRoutes.login;

      if (!isAuth && !isLoggingIn) {
        return AppRoutes.login;
      }
      if (isAuth && isLoggingIn) {
        return AppRoutes.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        builder: (context, state) {
          return Consumer(
            builder: (context, ref, child) {
              final authState = ref.watch(authControllerProvider);
              if (authState.isInitializing) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return const LoginScreen();
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        name: AppRoutes.dashboardName,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.transcription,
        name: AppRoutes.transcriptionName,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return TranscriptionScreen(
            doctorId: extra?['doctorId'] as String?,
            practiceCentreId: extra?['practiceCentreId'] as String?,
            clinicName: extra?['clinicName'] as String?,
          );
        },
      ),
    ],
  );
});

class AppRoutes {
  AppRoutes._();
  static const login = '/login';
  static const loginName = 'login';
  static const dashboard = '/dashboard';
  static const dashboardName = 'dashboard';
  static const transcription = '/transcription';
  static const transcriptionName = 'transcription';
}
