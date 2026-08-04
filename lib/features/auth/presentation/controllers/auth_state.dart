import '../../data/models/auth_token.dart';

enum AuthStatus {
  initializing,
  unauthenticated,
  authenticating,
  authenticated,
  error,
}

class AuthState {
  const AuthState({
    this.status = AuthStatus.initializing,
    this.token,
    this.errorMessage,
    this.isBiometricEnabled = false,
    this.isBiometricAvailable = false,
  });

  final AuthStatus status;
  final AuthToken? token;
  final String? errorMessage;
  final bool isBiometricEnabled;
  final bool isBiometricAvailable;

  bool get isInitializing => status == AuthStatus.initializing;
  bool get isAuthenticated => status == AuthStatus.authenticated && token != null;
  bool get isAuthenticating => status == AuthStatus.authenticating;

  String? get doctorId => token?.accountId;
  String? get doctorName => token?.fullName;
  String? get accessToken => token?.accessToken;
  String? get refreshToken => token?.refreshToken;

  AuthState copyWith({
    AuthStatus? status,
    AuthToken? token,
    bool clearToken = false,
    String? errorMessage,
    bool clearError = false,
    bool? isBiometricEnabled,
    bool? isBiometricAvailable,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: clearToken ? null : (token ?? this.token),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      isBiometricAvailable: isBiometricAvailable ?? this.isBiometricAvailable,
    );
  }
}
