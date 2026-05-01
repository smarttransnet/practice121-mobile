import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper around `permission_handler` so the rest of the app is decoupled
/// from the concrete plugin and gets a typed result.
class PermissionService {
  const PermissionService();

  /// Result of requesting the microphone permission.
  Future<MicPermissionResult> ensureMicrophone() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return MicPermissionResult.granted;

    if (status.isPermanentlyDenied) {
      return MicPermissionResult.permanentlyDenied;
    }

    final result = await Permission.microphone.request();
    if (result.isGranted) return MicPermissionResult.granted;
    if (result.isPermanentlyDenied) {
      return MicPermissionResult.permanentlyDenied;
    }
    return MicPermissionResult.denied;
  }

  /// Open the OS settings page so the user can grant permission manually
  /// after a permanent denial.
  Future<void> openSystemSettings() => openAppSettings();
}

enum MicPermissionResult { granted, denied, permanentlyDenied }
