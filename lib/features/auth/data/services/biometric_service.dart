import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../core/logging/app_logger.dart';

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

/// Encapsulates device biometric authentication (Face ID / Fingerprint / Touch ID).
class BiometricService {
  BiometricService({
    LocalAuthentication? auth,
  }) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// Checks whether hardware biometrics are supported and enrolled on this device.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } on PlatformException catch (e, stack) {
      AppLogger.e('BiometricService: platform error checking biometrics', e, stack);
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Prompts user for biometric authentication.
  /// Returns `true` if authentication succeeded, `false` otherwise.
  Future<bool> authenticate({
    String localizedReason = 'Please authenticate to unlock Practice121',
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        AppLogger.w('BiometricService: biometrics not available on device');
        return false;
      }

      final didAuthenticate = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          useErrorDialogs: true,
          biometricOnly: true,
        ),
      );

      AppLogger.i('BiometricService: authentication result = $didAuthenticate');
      return didAuthenticate;
    } on PlatformException catch (e, stack) {
      AppLogger.e('BiometricService: exception during biometric auth', e, stack);
      return false;
    } catch (e) {
      return false;
    }
  }
}
