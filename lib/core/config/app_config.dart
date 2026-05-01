/// Environment-driven configuration for the app.
///
/// All values can be overridden at run time without changing source code by
/// passing `--dart-define=KEY=value` flags to `flutter run` / `flutter build`.
/// This keeps secrets (or any per-environment values) out of the repository
/// and matches the React frontend's pattern of swapping the WebSocket URL
/// via Vite env variables.
class AppConfig {
  const AppConfig({
    required this.transcriptionWsUrl,
  });

  /// WebSocket endpoint for `/ws/transcribe` exposed by the .NET backend
  /// (see `Backend5/Program.cs` and `TranscriptionWebSocketHandler.cs`).
  final String transcriptionWsUrl;

  /// Loads configuration from `--dart-define` environment, falling back to
  /// the production Cloud Run URL used by the React frontend.
  factory AppConfig.fromEnvironment() {
    const wsUrl = String.fromEnvironment(
      'TRANSCRIPTION_WS_URL',
      defaultValue:
          'wss://note365-stt-api-687271578749.asia-southeast1.run.app/ws/transcribe',
    );
    return const AppConfig(transcriptionWsUrl: wsUrl);
  }
}
