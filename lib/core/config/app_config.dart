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
  /// the production Cloud Run URL used by the React frontend.
  factory AppConfig.fromEnvironment() {
    const wsUrl = String.fromEnvironment(
      'TRANSCRIPTION_WS_URL',
      defaultValue:
          'wss://note365-stt-api-687271578749.asia-southeast1.run.app/ws/transcribe',
    );

    const voiceCommandWsUrl = String.fromEnvironment(
      'VOICE_COMMAND_WS_URL',
      defaultValue:
          'wss://note365-stt-api-687271578749.asia-southeast1.run.app/ws/transcribe-command',
    );

    const amendUrl = String.fromEnvironment(
      'AMEND_URL',
      defaultValue:
          'https://note365-stt-api-687271578749.asia-southeast1.run.app/notes/amend',
    );

    const emailUrl = String.fromEnvironment(
      'EMAIL_URL',
      defaultValue:
          'https://note365-stt-api-687271578749.asia-southeast1.run.app/notes/email',
    );

    const smsUrl = String.fromEnvironment(
      'SMS_URL',
      defaultValue:
          'https://note365-stt-api-687271578749.asia-southeast1.run.app/notes/sms',
    );

    const fhirNotesUrl = String.fromEnvironment(
      'FHIR_NOTES_URL',
      defaultValue:
          'https://note365-stt-api-687271578749.asia-southeast1.run.app/notes/fhir',
    );

    const clientApiBaseUrl = String.fromEnvironment(
      'CLIENT_API_BASE_URL',
      defaultValue:
          'https://practice121-api-687271578749.asia-southeast1.run.app',
    );

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
