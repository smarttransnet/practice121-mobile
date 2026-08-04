import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/logging/app_logger.dart';
import '../models/auth_token.dart';

final authStorageServiceProvider = Provider<AuthStorageService>((ref) {
  return const AuthStorageService();
});

/// Manages secure persistence of auth tokens and authentication preferences.
///
/// Uses [FlutterSecureStorage] to protect tokens at rest.
/// Note: Raw passwords are NEVER stored.
class AuthStorageService {
  const AuthStorageService({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  static const String _keyAccessToken = 'auth_access_token';
  static const String _keyRefreshToken = 'auth_refresh_token';
  static const String _keyAccountId = 'auth_account_id';
  static const String _keyEmail = 'auth_email';
  static const String _keyFullName = 'auth_full_name';
  static const String _keyProfileCompletion = 'auth_profile_completion_status';
  static const String _keyBiometricEnabled = 'auth_biometric_enabled';

  /// Securely saves [token] data to encrypted storage.
  Future<void> saveAuthToken(AuthToken token) async {
    try {
      await Future.wait([
        _storage.write(key: _keyAccessToken, value: token.accessToken),
        _storage.write(key: _keyRefreshToken, value: token.refreshToken),
        _storage.write(key: _keyAccountId, value: token.accountId),
        _storage.write(key: _keyEmail, value: token.email),
        _storage.write(key: _keyFullName, value: token.fullName),
        _storage.write(
            key: _keyProfileCompletion, value: token.profileCompletionStatus),
      ]);
      AppLogger.i('AuthStorageService: auth tokens saved securely');
    } catch (e, stack) {
      AppLogger.e('AuthStorageService: failed to save tokens', e, stack);
      rethrow;
    }
  }

  /// Retrieves stored [AuthToken] credentials if present, or `null` if none found.
  Future<AuthToken?> getAuthToken() async {
    try {
      final accessToken = await _storage.read(key: _keyAccessToken);
      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }

      final refreshToken = await _storage.read(key: _keyRefreshToken) ?? '';
      final accountId = await _storage.read(key: _keyAccountId) ?? '';
      final email = await _storage.read(key: _keyEmail) ?? '';
      final fullName = await _storage.read(key: _keyFullName) ?? '';
      final profileCompletionStatus =
          await _storage.read(key: _keyProfileCompletion) ?? '';

      return AuthToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accountId: accountId,
        email: email,
        fullName: fullName,
        profileCompletionStatus: profileCompletionStatus,
      );
    } catch (e, stack) {
      AppLogger.e('AuthStorageService: failed to read tokens', e, stack);
      return null;
    }
  }

  /// Returns stored access token string or `null`.
  Future<String?> getAccessToken() async {
    try {
      return await _storage.read(key: _keyAccessToken);
    } catch (e) {
      return null;
    }
  }

  /// Returns stored refresh token string or `null`.
  Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _keyRefreshToken);
    } catch (e) {
      return null;
    }
  }

  /// Clears all stored auth credentials.
  Future<void> clearTokens() async {
    try {
      await Future.wait([
        _storage.delete(key: _keyAccessToken),
        _storage.delete(key: _keyRefreshToken),
        _storage.delete(key: _keyAccountId),
        _storage.delete(key: _keyEmail),
        _storage.delete(key: _keyFullName),
        _storage.delete(key: _keyProfileCompletion),
      ]);
      AppLogger.i('AuthStorageService: cleared auth tokens');
    } catch (e, stack) {
      AppLogger.e('AuthStorageService: error clearing tokens', e, stack);
    }
  }

  /// Reads whether biometric unlock is enabled by user preference (default: `false`).
  Future<bool> isBiometricEnabled() async {
    try {
      final value = await _storage.read(key: _keyBiometricEnabled);
      return value == 'true';
    } catch (e) {
      return false;
    }
  }

  /// Updates biometric unlock preference setting.
  Future<void> setBiometricEnabled(bool enabled) async {
    try {
      await _storage.write(
        key: _keyBiometricEnabled,
        value: enabled ? 'true' : 'false',
      );
      AppLogger.i('AuthStorageService: biometric enabled set to $enabled');
    } catch (e, stack) {
      AppLogger.e('AuthStorageService: error setting biometric preference', e, stack);
    }
  }
}
