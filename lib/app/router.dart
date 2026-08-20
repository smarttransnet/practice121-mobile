import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/transcription/presentation/screens/patient_queue_screen.dart';
import '../features/transcription/presentation/screens/transcription_screen.dart';
import '../features/patients/presentation/screens/patients_screen.dart';
import '../features/forms/presentation/screens/forms_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../design_system/widgets/app_shell.dart';

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
    // Start at login, it redirects to the shell if authenticated.
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
        // Redirect to the new shell's Queue tab instead of the old dashboard.
        return AppRoutes.shellQueue;
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
      
      // OLD ROUTES - Kept intact for backwards compatibility and deep links
      GoRoute(
        path: AppRoutes.dashboard,
        name: AppRoutes.dashboardName,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.patientQueue,
        name: AppRoutes.patientQueueName,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PatientQueueScreen(
            doctorId: extra?['doctorId'] as String? ?? '',
            practiceCentreId: extra?['practiceCentreId'] as String? ?? '',
            clinicName: extra?['clinicName'] as String? ?? 'Practice Centre',
          );
        },
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

      // NEW SHELL ROUTE
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shellQueue,
                builder: (context, state) => const PatientQueueScreen(
                  doctorId: '',
                  practiceCentreId: '',
                  clinicName: 'Practice Centre',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shellSchedule,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shellPatients,
                builder: (context, state) => const PatientsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shellForms,
                builder: (context, state) => const FormsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shellProfile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class AppRoutes {
  AppRoutes._();
  static const login = '/login';
  static const loginName = 'login';
  
  // Old routes
  static const dashboard = '/dashboard';
  static const dashboardName = 'dashboard';
  static const patientQueue = '/patient-queue';
  static const patientQueueName = 'patientQueue';
  static const transcription = '/transcription';
  static const transcriptionName = 'transcription';
  
  // New shell routes
  static const shellQueue = '/shell/queue';
  static const shellSchedule = '/shell/schedule';
  static const shellPatients = '/shell/patients';
  static const shellForms = '/shell/forms';
  static const shellProfile = '/shell/profile';
}
