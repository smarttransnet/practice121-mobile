import 'dart:async';

import '../../../../core/config/app_config.dart';
import '../../../../core/logging/app_logger.dart';
import '../services/audio_capture_service.dart';
import '../services/voice_command_socket_service.dart';

class VoiceCommandRepository {
  VoiceCommandRepository({
    required AppConfig appConfig,
    required AudioCaptureService audioCaptureService,
    required VoiceCommandSocketService socketService,
  })  : _appConfig = appConfig,
        _audio = audioCaptureService,
        _socket = socketService;

  final AppConfig _appConfig;
  final AudioCaptureService _audio;
  final VoiceCommandSocketService _socket;

  StreamSubscription<AudioFrame>? _audioSub;
  bool _disposed = false;

  Future<Stream<VoiceCommandEvent>> startSession() async {
    AppLogger.i('VoiceCommandRepository.startSession()');

    final eventStream = await _socket.connect(
      url: Uri.parse(_appConfig.voiceCommandWsUrl),
    );

    final Stream<AudioFrame> audioStream;
    try {
      audioStream = await _audio.start();
    } catch (e) {
      await _socket.close();
      rethrow;
    }

    _audioSub = audioStream.listen(
      (frame) {
        _socket.sendAudioFrame(frame.bytes);
      },
      onError: (Object error, StackTrace stack) {
        AppLogger.e('Audio capture errored in voice command', error, stack);
      },
      cancelOnError: false,
    );

    return eventStream;
  }

  Future<void> stopSession() async {
    AppLogger.i('VoiceCommandRepository.stopSession()');
    await _audioSub?.cancel();
    _audioSub = null;
    await _audio.stop();
    await _socket.sendStop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    AppLogger.i('VoiceCommandRepository.dispose()');

    try {
      await _audioSub?.cancel();
    } catch (_) {}
    _audioSub = null;

    await _audio.stop();
    await _socket.close();
  }
}
