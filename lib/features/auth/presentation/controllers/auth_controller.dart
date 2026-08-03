import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/services/auth_service.dart';
import 'auth_state.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final config = ref.watch(appConfigProvider);
  final authService = ref.watch(authServiceProvider);
  return AuthController(
    authService: authService,
    config: config,
  );
});

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required AuthService authService,
    required AppConfig config,
  })  : _authService = authService,
        _config = config,
        super(const AuthState());

  final AuthService _authService;
  final AppConfig _config;

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );

    try {
      final token = await _authService.login(
        baseUrl: _config.clientApiBaseUrl,
        email: email,
        password: password,
      );

      state = state.copyWith(
        status: AuthStatus.authenticated,
        token: token,
      );
      return true;
    } catch (e) {
      AppLogger.e('AuthController: login error — $e');
      final message =
          e is Failure ? e.message : 'Invalid email or password. Please try again.';
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: message,
      );
      return false;
    }
  }

  void logout() {
    AppLogger.i('AuthController: logout called');
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void dismissError() {
    state = state.copyWith(clearError: true);
  }
}
