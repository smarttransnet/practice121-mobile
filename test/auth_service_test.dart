import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note365_mobile/core/errors/failures.dart';
import 'package:note365_mobile/features/auth/data/services/auth_service.dart';

void main() {
  group('AuthService HTTP Error Handling Tests', () {
    const baseUrl = 'https://api.practice121.test';

    test('HTTP 503 HTML response throws friendly service unavailable message', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '<html><head><title>503 Service Unavailable</title></head><body>Service Unavailable</body></html>',
          503,
          headers: {'content-type': 'text/html'},
        );
      });

      final authService = AuthService(httpClient: mockClient);

      expect(
        () => authService.login(
          baseUrl: baseUrl,
          email: 'test@test.com',
          password: 'password123',
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (f) => f.message,
            'message',
            contains('The service is temporarily unavailable (503)'),
          ),
        ),
      );
    });

    test('HTTP 502 Bad Gateway response throws gateway error message', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Bad Gateway', 502);
      });

      final authService = AuthService(httpClient: mockClient);

      expect(
        () => authService.login(
          baseUrl: baseUrl,
          email: 'test@test.com',
          password: 'password123',
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (f) => f.message,
            'message',
            contains('Unable to connect to the server (502)'),
          ),
        ),
      );
    });

    test('HTTP 500 Internal Server Error throws server error message', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final authService = AuthService(httpClient: mockClient);

      expect(
        () => authService.login(
          baseUrl: baseUrl,
          email: 'test@test.com',
          password: 'password123',
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (f) => f.message,
            'message',
            contains('A server error occurred (500)'),
          ),
        ),
      );
    });

    test('HTTP 400 Bad Request with JSON error message parses description', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'Doctor.InvalidCredentials',
              'message': 'Invalid email or password.',
            },
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final authService = AuthService(httpClient: mockClient);

      expect(
        () => authService.login(
          baseUrl: baseUrl,
          email: 'test@test.com',
          password: 'wrongpassword',
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (f) => f.message,
            'message',
            equals('Invalid email or password.'),
          ),
        ),
      );
    });

    test('HTTP 200 OK returns valid AuthToken', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'accessToken': 'jwt-access-token-123',
              'refreshToken': 'refresh-token-456',
              'accountId': 'acc-12345',
              'email': 'doctor@example.com',
              'fullName': 'Dr. John Doe',
              'profileCompletionStatus': 'Complete',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final authService = AuthService(httpClient: mockClient);

      final token = await authService.login(
        baseUrl: baseUrl,
        email: 'doctor@example.com',
        password: 'correctpassword',
      );

      expect(token.accessToken, equals('jwt-access-token-123'));
      expect(token.refreshToken, equals('refresh-token-456'));
      expect(token.accountId, equals('acc-12345'));
      expect(token.fullName, equals('Dr. John Doe'));
    });

    test('Google login with HTTP 503 throws service unavailable', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Service Unavailable', 503);
      });

      final authService = AuthService(httpClient: mockClient);

      expect(
        () => authService.googleLogin(
          baseUrl: baseUrl,
          idToken: 'google-id-token-abc',
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (f) => f.message,
            'message',
            contains('The service is temporarily unavailable (503)'),
          ),
        ),
      );
    });

    test('Refresh token with HTTP 503 throws service unavailable without expiring session', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Service Unavailable', 503);
      });

      final authService = AuthService(httpClient: mockClient);

      expect(
        () => authService.refreshToken(
          baseUrl: baseUrl,
          refreshToken: 'refresh-token-xyz',
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (f) => f.message,
            'message',
            contains('The service is temporarily unavailable (503)'),
          ),
        ),
      );
    });
  });
}
