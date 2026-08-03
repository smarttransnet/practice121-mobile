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
    required this.clientApiBaseUrl,
  });

  /// Base REST endpoint for Practice121 Client-API (auth, practice centres, queue).
  final String clientApiBaseUrl;

  /// WebSocket endpoint for `/ws/transcribe` (paediatric Sinhala + Gemini).
  final String transcriptionWsUrl;

  /// WebSocket endpoint for `/ws/transcribe-command` (English STT-only).
  final String voiceCommandWsUrl;

  /// REST endpoint for `/notes/amend` (POST command + note).
  final String amendUrl;

  /// REST endpoint for `/notes/email` (POST summary).
  final String emailUrl;

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

    const clientApiBaseUrl = String.fromEnvironment(
      'CLIENT_API_BASE_URL',
      defaultValue:
          'https://practice121-api-687271578749.asia-southeast1.run.app',
    );

    AppLogger.i('AppConfig: clientApiBaseUrl=$clientApiBaseUrl');
    AppLogger.i('AppConfig: transcriptionWsUrl=$wsUrl');
    AppLogger.i('AppConfig: voiceCommandWsUrl=$voiceCommandWsUrl');
    AppLogger.i('AppConfig: amendUrl=$amendUrl');
    AppLogger.i('AppConfig: emailUrl=$emailUrl');

    return AppConfig(
      clientApiBaseUrl: clientApiBaseUrl,
      transcriptionWsUrl: wsUrl,
      voiceCommandWsUrl: voiceCommandWsUrl,
      amendUrl: amendUrl,
      emailUrl: emailUrl,
    );
  }
}
