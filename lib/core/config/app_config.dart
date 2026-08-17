import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';

/// Top-level app config provider.
final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

/// Centralized configuration for the application.
class AppConfig {
  const AppConfig({
    required this.transcriptionWsUrl,
    required this.voiceCommandWsUrl,
    required this.amendUrl,
    required this.emailUrl,
    required this.smsUrl,
    required this.fhirNotesUrl,
    required this.clientApiBaseUrl,
    required this.googleServerClientId,
    required this.privacyPolicyUrl,
    required this.accountDeletionUrl,
  });

  /// Base REST endpoint for Practice121 Client-API (auth, practice centres, queue).
  final String clientApiBaseUrl;

  /// Google Cloud **Web** OAuth client ID. Required on Android to obtain an
  /// ID token for `POST /api/auth/google`.
  final String googleServerClientId;

  /// Public HTTPS privacy policy (also required on the Play Store listing).
  final String privacyPolicyUrl;

  /// Public HTTPS account-deletion request page (Play User Data policy).
  final String accountDeletionUrl;

  bool get hasPrivacyPolicy => privacyPolicyUrl.trim().isNotEmpty;

  bool get hasAccountDeletionUrl => accountDeletionUrl.trim().isNotEmpty;

  /// WebSocket endpoint for `/ws/transcribe` (paediatric Sinhala + Gemini).
  final String transcriptionWsUrl;

  /// WebSocket endpoint for `/ws/transcribe-command` (English STT-only).
  final String voiceCommandWsUrl;

  /// REST endpoint for `/notes/amend` (POST command + note).
  final String amendUrl;

  /// REST endpoint for `/notes/email` (POST summary).
  final String emailUrl;

  /// REST endpoint for `/notes/sms` (POST summary).
  final String smsUrl;

  /// REST endpoint for `/notes/fhir` (POST save / GET list).
  final String fhirNotesUrl;

  /// Loads configuration from `--dart-define` environment, falling back to
  /// the production Cloud Run URL used by the React frontend if in release mode,
  /// or localhost if in debug mode.
  factory AppConfig.fromEnvironment() {
    final isLocalWeb = kIsWeb && (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1');
    final useLocal = kDebugMode || isLocalWeb;

    final wsUrl = const String.fromEnvironment('TRANSCRIPTION_WS_URL', defaultValue: '') != ''
        ? const String.fromEnvironment('TRANSCRIPTION_WS_URL')
        : (useLocal
            ? 'ws://localhost:5005/ws/transcribe'
            : 'wss://note365-stt-api-687271578749.asia-southeast1.run.app/ws/transcribe');

    final voiceCommandWsUrl = const String.fromEnvironment('VOICE_COMMAND_WS_URL', defaultValue: '') != ''
        ? const String.fromEnvironment('VOICE_COMMAND_WS_URL')
        : (useLocal
            ? 'ws://localhost:5005/ws/transcribe-command'
            : 'wss://note365-stt-api-687271578749.asia-southeast1.run.app/ws/transcribe-command');

    final amendUrl = const String.fromEnvironment('AMEND_URL', defaultValue: '') != ''
        ? const String.fromEnvironment('AMEND_URL')
        : (useLocal
            ? 'http://localhost:5005/notes/amend'
            : 'https://note365-stt-api-687271578749.asia-southeast1.run.app/notes/amend');

    final emailUrl = const String.fromEnvironment('EMAIL_URL', defaultValue: '') != ''
        ? const String.fromEnvironment('EMAIL_URL')
        : (useLocal
            ? 'http://localhost:5005/notes/email'
            : 'https://note365-stt-api-687271578749.asia-southeast1.run.app/notes/email');

    final smsUrl = const String.fromEnvironment('SMS_URL', defaultValue: '') != ''
        ? const String.fromEnvironment('SMS_URL')
        : (useLocal
            ? 'http://localhost:5005/notes/sms'
            : 'https://note365-stt-api-687271578749.asia-southeast1.run.app/notes/sms');

    final fhirNotesUrl = const String.fromEnvironment('FHIR_NOTES_URL', defaultValue: '') != ''
        ? const String.fromEnvironment('FHIR_NOTES_URL')
        : (useLocal
            ? 'http://localhost:5005/notes/fhir'
            : 'https://note365-stt-api-687271578749.asia-southeast1.run.app/notes/fhir');

    final clientApiBaseUrl = const String.fromEnvironment('CLIENT_API_BASE_URL', defaultValue: '') != ''
        ? const String.fromEnvironment('CLIENT_API_BASE_URL')
        : (useLocal
            ? 'http://localhost:5000'
            : 'https://practice121-api-687271578749.asia-southeast1.run.app');

    const googleServerClientId = String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    );

    const privacyPolicyUrl = String.fromEnvironment(
      'PRIVACY_POLICY_URL',
    );

    const accountDeletionUrl = String.fromEnvironment(
      'ACCOUNT_DELETION_URL',
    );

    AppLogger.i('AppConfig: clientApiBaseUrl=$clientApiBaseUrl');
    AppLogger.i('AppConfig: transcriptionWsUrl=$wsUrl');
    AppLogger.i('AppConfig: voiceCommandWsUrl=$voiceCommandWsUrl');
    AppLogger.i('AppConfig: amendUrl=$amendUrl');
    AppLogger.i('AppConfig: emailUrl=$emailUrl');
    AppLogger.i('AppConfig: smsUrl=$smsUrl');
    AppLogger.i('AppConfig: fhirNotesUrl=$fhirNotesUrl');
    AppLogger.i(
      'AppConfig: googleServerClientId=${googleServerClientId.isEmpty ? '(unset)' : '(set)'}',
    );

    return AppConfig(
      clientApiBaseUrl: clientApiBaseUrl,
      transcriptionWsUrl: wsUrl,
      voiceCommandWsUrl: voiceCommandWsUrl,
      amendUrl: amendUrl,
      emailUrl: emailUrl,
      smsUrl: smsUrl,
      fhirNotesUrl: fhirNotesUrl,
      googleServerClientId: googleServerClientId,
      privacyPolicyUrl: privacyPolicyUrl,
      accountDeletionUrl: accountDeletionUrl,
    );
  }
}
