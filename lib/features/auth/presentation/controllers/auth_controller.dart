import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../data/models/auth_token.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/auth_storage_service.dart';
import '../../data/services/biometric_service.dart';
import 'auth_state.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final config = ref.watch(appConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final storageService = ref.watch(authStorageServiceProvider);
  final biometricService = ref.watch(biometricServiceProvider);

  final controller = AuthController(
    authService: authService,
    storageService: storageService,
    biometricService: biometricService,
    config: config,
  );

  // Hook ApiClient 401 callback to auto-logout
  ref.watch(apiClientProvider).setOnUnauthorized(() {
    controller.logout();
  });

  return controller;
});

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required AuthService authService,
    required AuthStorageService storageService,
    required BiometricService biometricService,
    required AppConfig config,
  })  : _authService = authService,
        _storageService = storageService,
        _biometricService = biometricService,
        _config = config,
        super(const AuthState());

  final AuthService _authService;
  final AuthStorageService _storageService;
  final BiometricService _biometricService;
  final AppConfig _config;

  /// Checks for an existing session on app launch and validates biometrics if enabled.
  Future<void> initializeSession() async {
    state = state.copyWith(status: AuthStatus.initializing);

    try {
      final isBiometricAvail = await _biometricService.isBiometricAvailable();
      final isBiometricOn = await _storageService.isBiometricEnabled();

      state = state.copyWith(
        isBiometricAvailable: isBiometricAvail,
        isBiometricEnabled: isBiometricOn,
      );

      final storedToken = await _storageService.getAuthToken();
      if (storedToken == null || storedToken.accessToken.isEmpty) {
        AppLogger.i('AuthController: no stored token found');
        state = state.copyWith(status: AuthStatus.unauthenticated);
        return;
      }

      // Check biometric authentication if enabled
      if (isBiometricOn && isBiometricAvail) {
        final bioAuthenticated = await _biometricService.authenticate(
          localizedReason: 'Authenticate to access Note365',
        );

        if (!bioAuthenticated) {
          AppLogger.w('AuthController: biometric unlock failed/cancelled — falling back to login screen');
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
          );
          return;
        }
      }

      // Attempt token refresh or validate stored token
      AuthToken activeToken = storedToken;
      if (storedToken.refreshToken.isNotEmpty) {
        try {
          activeToken = await _authService.refreshToken(
            baseUrl: _config.clientApiBaseUrl,
            refreshToken: storedToken.refreshToken,
          );
          await _storageService.saveAuthToken(activeToken);
        } catch (e) {
          AppLogger.w('AuthController: refresh on init failed — checking if stored token is still usable: $e');
          // If refresh failed, test if access token exists, otherwise require re-login
          if (storedToken.accessToken.isEmpty) {
            await _storageService.clearTokens();
            state = state.copyWith(
              status: AuthStatus.unauthenticated,
              clearToken: true,
            );
            return;
          }
        }
      }

      AppLogger.i('AuthController: session restored for doctorId=${activeToken.accountId}');
      state = state.copyWith(
        status: AuthStatus.authenticated,
        token: activeToken,
      );
    } catch (e, stack) {
      AppLogger.e('AuthController: exception during session initialization', e, stack);
      await _storageService.clearTokens();
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearToken: true,
      );
    }
  }

  /// Authenticates user via email/password and saves returned tokens securely.
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

      await _storageService.saveAuthToken(token);

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

  /// Authenticates user using Google Sign-In library and exchanges ID Token with backend.
  Future<bool> loginWithGoogle() async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );

    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );

      // Trigger native sign in modal
      final account = await googleSignIn.signIn();
      if (account == null) {
        // User cancelled Google sign-in flow
        AppLogger.i('AuthController: Google sign-in cancelled by user');
        state = state.copyWith(status: AuthStatus.unauthenticated);
        return false;
      }

      final authDetails = await account.authentication;
      final idToken = authDetails.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const UnexpectedFailure('Could not retrieve authentication token from Google.');
      }

      final token = await _authService.googleLogin(
        baseUrl: _config.clientApiBaseUrl,
        idToken: idToken,
      );

      await _storageService.saveAuthToken(token);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        token: token,
      );
      return true;
    } catch (e) {
      AppLogger.e('AuthController: Google login error — $e');
      final message = e is Failure
          ? e.message
          : 'This Google account is not registered. Please register through the Web application or contact your administrator.';
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: message,
      );
      return false;
    }
  }

  /// Logs out user, revokes server token, and clears secure storage.
  Future<void> logout() async {
    AppLogger.i('AuthController: logout initiated');
    final currentRefreshToken = state.refreshToken ?? await _storageService.getRefreshToken();

    // Revoke server token
    await _authService.logout(
      baseUrl: _config.clientApiBaseUrl,
      refreshToken: currentRefreshToken,
    );

    // Clear secure storage
    await _storageService.clearTokens();

    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      clearToken: true,
    );
  }

  /// Enables or disables biometric unlock preference.
  Future<void> setBiometricEnabled(bool enabled) async {
    await _storageService.setBiometricEnabled(enabled);
    state = state.copyWith(isBiometricEnabled: enabled);
  }

  void dismissError() {
    state = state.copyWith(clearError: true);
  }
}
