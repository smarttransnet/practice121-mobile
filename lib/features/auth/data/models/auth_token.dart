/// Represents authentication credentials and doctor profile metadata returned by
/// `POST api/auth/login`.
class AuthToken {
  const AuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.accountId,
    required this.email,
    required this.fullName,
    required this.profileCompletionStatus,
  });

  final String accessToken;
  final String refreshToken;
  final String accountId;
  final String email;
  final String fullName;
  final String profileCompletionStatus;

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    final payload = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;

    return AuthToken(
      accessToken: payload['accessToken']?.toString() ?? '',
      refreshToken: payload['refreshToken']?.toString() ?? '',
      accountId: payload['accountId']?.toString() ?? '',
      email: payload['email']?.toString() ?? '',
      fullName: payload['fullName']?.toString() ?? '',
      profileCompletionStatus:
          payload['profileCompletionStatus']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'accountId': accountId,
      'email': email,
      'fullName': fullName,
      'profileCompletionStatus': profileCompletionStatus,
    };
  }
}
