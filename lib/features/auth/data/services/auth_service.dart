import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../models/auth_token.dart';

/// Interacts with the Practice121 Auth API for Doctor authentication.
class AuthService {
  AuthService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  /// Helper to extract user-friendly error messages from HTTP error responses.
  /// Categorizes infrastructure errors (503, 502, 504, 500) and extracts structured JSON details when available.
  String _parseHttpErrorMessage(
    http.Response response, {
    required String defaultMessage,
  }) {
    String errorMessage;
    if (response.statusCode == 503) {
      errorMessage =
          'The service is temporarily unavailable (503). Please try again in a few moments.';
    } else if (response.statusCode == 502 || response.statusCode == 504) {
      errorMessage =
          'Unable to connect to the server (${response.statusCode}). Please check your connection or try again later.';
    } else if (response.statusCode == 500) {
      errorMessage =
          'A server error occurred (500). Please try again later.';
    } else if (response.statusCode == 401) {
      errorMessage = 'Invalid email or password.';
    } else {
      errorMessage = defaultMessage;
    }

    try {
      final errBody = jsonDecode(response.body);
      if (errBody is Map<String, dynamic>) {
        if (errBody['error'] != null) {
          final errVal = errBody['error'];
          if (errVal is Map<String, dynamic> && errVal['message'] != null) {
            errorMessage = errVal['message'].toString();
          } else {
            errorMessage = errVal.toString();
          }
        } else if (errBody['detail'] != null) {
          errorMessage = errBody['detail'].toString();
        } else if (errBody['title'] != null) {
          errorMessage = errBody['title'].toString();
        } else if (errBody['message'] != null) {
          errorMessage = errBody['message'].toString();
        }
      }
    } catch (_) {
      // Non-JSON bodies (e.g. Cloud Run 503 HTML error pages) retain the friendly status code message
    }

    return errorMessage;
  }

  /// Authenticates a doctor using [email] and [password].
  ///
  /// Calls `POST /api/auth/login` and returns an [AuthToken].
  Future<AuthToken> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw const UnexpectedFailure('Email address is required.');
    }
    if (password.isEmpty) {
      throw const UnexpectedFailure('Password is required.');
    }

    final uri = Uri.parse('$baseUrl/api/auth/login');
    AppLogger.i('AuthService: login attempt for $cleanEmail -> $uri');

    try {
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': cleanEmail,
          'password': password,
        }),
      );

      if (response.statusCode != 200) {
        final errorMessage = _parseHttpErrorMessage(
          response,
          defaultMessage: 'Authentication failed (${response.statusCode}).',
        );
        AppLogger.w('AuthService: login failed — $errorMessage');
        throw UnexpectedFailure(errorMessage);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] == false) {
        String errorMessage = 'Authentication failed.';
        final errObj = data['error'];
        if (errObj is Map<String, dynamic> && errObj['message'] != null) {
          errorMessage = errObj['message'].toString();
        } else if (errObj != null) {
          errorMessage = errObj.toString();
        }
        AppLogger.w('AuthService: login failed — $errorMessage');
        throw UnexpectedFailure(errorMessage);
      }

      final token = AuthToken.fromJson(data);

      AppLogger.i(
          'AuthService: login successful — doctorId=${token.accountId}, name=${token.fullName}');
      return token;
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('AuthService: network or unexpected error during login', e, stack);
      throw UnexpectedFailure(
          'Unable to connect to authentication server. Please check your connection.');
    }
  }

  /// Authenticates a doctor using Google [idToken].
  ///
  /// Calls `POST /api/auth/google` and returns an [AuthToken].
  Future<AuthToken> googleLogin({
    required String baseUrl,
    required String idToken,
  }) async {
    if (idToken.trim().isEmpty) {
      throw const UnexpectedFailure('Google authentication token is missing.');
    }

    final uri = Uri.parse('$baseUrl/api/auth/google');
    AppLogger.i('AuthService: Google login attempt -> $uri');

    try {
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': idToken,
        }),
      );

      if (response.statusCode != 200) {
        final errorMessage = _parseHttpErrorMessage(
          response,
          defaultMessage:
              'This Google account is not registered. Please register through the Web application or contact your administrator.',
        );
        AppLogger.w('AuthService: Google login failed (${response.statusCode}) — $errorMessage');
        throw UnexpectedFailure(errorMessage);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] == false) {
        String errorMessage =
            'This Google account is not registered. Please register through the Web application or contact your administrator.';
        final errObj = data['error'];
        if (errObj is Map<String, dynamic> && errObj['message'] != null) {
          errorMessage = errObj['message'].toString();
        } else if (errObj != null) {
          errorMessage = errObj.toString();
        }
        AppLogger.w('AuthService: Google login failed — $errorMessage');
        throw UnexpectedFailure(errorMessage);
      }

      final token = AuthToken.fromJson(data);

      AppLogger.i(
          'AuthService: Google login successful — doctorId=${token.accountId}, name=${token.fullName}');
      return token;
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('AuthService: error during Google login', e, stack);
      throw UnexpectedFailure(
          'Unable to connect to authentication server. Please check your connection.');
    }
  }

  /// Refreshes access token using [refreshToken].
  ///
  /// Calls `POST /api/auth/refresh-token` and returns renewed [AuthToken].
  Future<AuthToken> refreshToken({
    required String baseUrl,
    required String refreshToken,
  }) async {
    if (refreshToken.isEmpty) {
      throw const UnexpectedFailure('Refresh token is required.');
    }

    final uri = Uri.parse('$baseUrl/api/auth/refresh-token');
    AppLogger.i('AuthService: refreshing access token via $uri');

    try {
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refreshToken': refreshToken,
        }),
      );

      if (response.statusCode != 200) {
        AppLogger.w('AuthService: token refresh HTTP error ${response.statusCode}');
        if (response.statusCode == 503 ||
            response.statusCode == 502 ||
            response.statusCode == 504) {
          throw UnexpectedFailure(
              'The service is temporarily unavailable (${response.statusCode}). Please try again shortly.');
        }
        throw UnexpectedFailure('Session expired (${response.statusCode}). Please log in again.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == false) {
        AppLogger.w('AuthService: token refresh rejected by server');
        throw const UnexpectedFailure('Session expired. Please log in again.');
      }

      final token = AuthToken.fromJson(data);
      AppLogger.i('AuthService: token refresh successful');
      return token;
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('AuthService: error during token refresh', e, stack);
      throw UnexpectedFailure('Unable to refresh session. Please log in again.');
    }
  }

  /// Calls backend token revocation endpoint `POST /api/auth/logout`.
  Future<void> logout({
    required String baseUrl,
    required String? refreshToken,
  }) async {
    if (refreshToken == null || refreshToken.isEmpty) {
      return;
    }

    final uri = Uri.parse('$baseUrl/api/auth/logout');
    AppLogger.i('AuthService: revoking session via $uri');

    try {
      await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refreshToken': refreshToken,
        }),
      );
    } catch (e) {
      // Log failure but do not throw - client side cleanup must proceed regardless
      AppLogger.w('AuthService: failed to notify server of logout: $e');
    }
  }
}
