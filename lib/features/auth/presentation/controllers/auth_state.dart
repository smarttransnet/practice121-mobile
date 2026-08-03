import '../../data/models/auth_token.dart';

enum AuthStatus {
  unauthenticated,
  authenticating,
  authenticated,
  error,
}

class AuthState {
  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.token,
    this.errorMessage,
  });

  final AuthStatus status;
  final AuthToken? token;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated && token != null;
  bool get isAuthenticating => status == AuthStatus.authenticating;

  String? get doctorId => token?.accountId;
  String? get doctorName => token?.fullName;
  String? get accessToken => token?.accessToken;

  AuthState copyWith({
    AuthStatus? status,
    AuthToken? token,
    bool clearToken = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: clearToken ? null : (token ?? this.token),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
