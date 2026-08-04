import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../features/auth/data/models/auth_token.dart';
import '../../features/auth/data/services/auth_service.dart';
import '../../features/auth/data/services/auth_storage_service.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../config/app_config.dart';
import '../errors/failures.dart';
import '../logging/app_logger.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final storageService = ref.watch(authStorageServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final config = ref.watch(appConfigProvider);

  return ApiClient(
    storageService: storageService,
    authService: authService,
    config: config,
  );
});

/// Authenticated HTTP client wrapper that auto-attaches JWT bearer headers
/// and handles automatic 401 token refresh.
class ApiClient {
  ApiClient({
    required AuthStorageService storageService,
    required AuthService authService,
    required AppConfig config,
    http.Client? client,
    void Function()? onUnauthorized,
  })  : _storageService = storageService,
        _authService = authService,
        _config = config,
        _client = client ?? http.Client(),
        _onUnauthorized = onUnauthorized;

  final AuthStorageService _storageService;
  final AuthService _authService;
  final AppConfig _config;
  final http.Client _client;
  void Function()? _onUnauthorized;

  void setOnUnauthorized(void Function() callback) {
    _onUnauthorized = callback;
  }

  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    return _sendWithRetry((h) => _client.get(url, headers: h), headers);
  }

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    return _sendWithRetry(
      (h) => _client.post(url, headers: h, body: body, encoding: encoding),
      headers,
    );
  }

  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    return _sendWithRetry(
      (h) => _client.put(url, headers: h, body: body, encoding: encoding),
      headers,
    );
  }

  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    return _sendWithRetry(
      (h) => _client.delete(url, headers: h, body: body, encoding: encoding),
      headers,
    );
  }

  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function(Map<String, String> headers) requestFn,
    Map<String, String>? initialHeaders,
  ) async {
    final headers = Map<String, String>.from(initialHeaders ?? {});
    final accessToken = await _storageService.getAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    var response = await requestFn(headers);

    if (response.statusCode == 401) {
      AppLogger.w('ApiClient: received 401 Unauthorized — attempting token refresh');
      final refreshedToken = await _tryRefreshToken();

      if (refreshedToken != null) {
        headers['Authorization'] = 'Bearer ${refreshedToken.accessToken}';
        AppLogger.i('ApiClient: retrying request with refreshed access token');
        response = await requestFn(headers);
      } else {
        AppLogger.w('ApiClient: token refresh failed — notifying unauthorized state');
        _onUnauthorized?.call();
        throw const UnexpectedFailure('Session expired. Please log in again.');
      }
    }

    return response;
  }

  Future<AuthToken?> _tryRefreshToken() async {
    try {
      final refreshTokenStr = await _storageService.getRefreshToken();
      if (refreshTokenStr == null || refreshTokenStr.isEmpty) {
        return null;
      }

      final newToken = await _authService.refreshToken(
        baseUrl: _config.clientApiBaseUrl,
        refreshToken: refreshTokenStr,
      );

      await _storageService.saveAuthToken(newToken);
      return newToken;
    } catch (e) {
      AppLogger.e('ApiClient: error refreshing token: $e');
      return null;
    }
  }
}
