import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../models/auth_token.dart';

/// Interacts with the Practice121 Auth API for Doctor authentication.
class AuthService {
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
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': cleanEmail,
          'password': password,
        }),
      );

      if (response.statusCode != 200) {
        String errorMessage =
            'Authentication failed (${response.statusCode}).';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map<String, dynamic>) {
            if (errBody['error'] != null) {
              errorMessage = errBody['error'].toString();
            } else if (errBody['detail'] != null) {
              errorMessage = errBody['detail'].toString();
            } else if (errBody['title'] != null) {
              errorMessage = errBody['title'].toString();
            }
          }
        } catch (_) {
          // ignore non-json body
        }
        AppLogger.w('AuthService: login failed — $errorMessage');
        throw UnexpectedFailure(errorMessage);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
}
