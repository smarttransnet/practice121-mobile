import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper around `permission_handler` so the rest of the app is decoupled
/// from the concrete plugin and gets a typed result.
class PermissionService {
  const PermissionService();

  /// Play / User Data policy: disclose mic + clinical-audio use *before* the
  /// OS permission prompt.
  static Future<bool> confirmMicrophoneDisclosure(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Microphone access'),
          content: Text(
            'Practice121 records the consultation on this device and streams '
            'audio to our secure servers to generate a draft clinical note. '
            'Audio and transcripts are health information. Recording starts '
            'only after you tap Allow, and you can stop at any time.\n\n'
            'Draft notes are AI-generated and must be reviewed by a licensed '
            'clinician before use in care.',
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<bool> isMicrophoneGranted() => Permission.microphone.isGranted;

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
