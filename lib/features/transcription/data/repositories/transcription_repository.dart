import 'dart:async';

import '../../../../core/config/app_config.dart';
import '../../../../core/logging/app_logger.dart';
import '../models/session_config.dart';
import '../models/transcription_event.dart';
import '../services/audio_capture_service.dart';
import '../services/transcription_socket_service.dart';

/// Composes the audio capture service and the WebSocket service into a single
/// repository surface that the controller layer can drive.
///
/// Lifecycle:
///   • [startSession] opens a WS connection, requests microphone audio, and
///     forwards each captured PCM frame to the server. Returns two streams:
///       - [TranscriptionSession.events] for transcription/note results
///       - [TranscriptionSession.audioLevels] for the visualizer (RMS 0..1)
///   • [stopSession] sends `STOP` to the server, awaits the final note, then
///     tears everything down. The events stream completes naturally when the
///     server sends the final note frame and closes the socket.
class TranscriptionRepository {
  TranscriptionRepository({
    required AppConfig appConfig,
    required AudioCaptureService audioCaptureService,
    required TranscriptionSocketService socketService,
  })  : _appConfig = appConfig,
        _audio = audioCaptureService,
        _socket = socketService;

  final AppConfig _appConfig;
  final AudioCaptureService _audio;
  final TranscriptionSocketService _socket;

  StreamSubscription<AudioFrame>? _audioSub;
  StreamController<double>? _levelsController;
  StreamController<int>? _byteCountController;

  bool _disposed = false;

  /// Open the session. Throws on connection / mic failures.
  Future<TranscriptionSession> startSession({
    required SessionConfig config,
  }) async {
    AppLogger.i('TranscriptionRepository.startSession()');

    final eventStream = await _socket.connect(
      url: Uri.parse(_appConfig.transcriptionWsUrl),
      config: config,
    );

    final Stream<AudioFrame> audioStream;
    try {
      audioStream = await _audio.start();
    } catch (e) {
      // Clean up the WS we just opened if mic init fails.
      await _socket.close();
      rethrow;
    }

    _levelsController = StreamController<double>.broadcast();
    _byteCountController = StreamController<int>.broadcast();

    _audioSub = audioStream.listen(
      (frame) {
        _socket.sendAudioFrame(frame.bytes);
        _levelsController?.add(frame.rms);
        _byteCountController?.add(frame.bytes.length);
      },
      onError: (Object error, StackTrace stack) {
        AppLogger.e('Audio capture errored mid-session', error, stack);
        _levelsController?.addError(error, stack);
      },
      onDone: () {
        AppLogger.i('Audio capture stream done');
      },
      cancelOnError: false,
    );

    return TranscriptionSession(
      events: eventStream,
      audioLevels: _levelsController!.stream,
      audioBytes: _byteCountController!.stream,
    );
  }

  /// End the session: stop sending audio, ask the server to finalize, and
  /// tear down resources. The caller still receives the final processed-note
  /// event on the [TranscriptionSession.events] stream before it closes.
  Future<void> stopSession() async {
    AppLogger.i('TranscriptionRepository.stopSession()');
    // Stop pushing new audio first so no straggler frames arrive after STOP.
    await _audioSub?.cancel();
    _audioSub = null;
    await _audio.stop();
    await _socket.sendStop();

    // Don't close the WS yet — the server still has to send the final
    // `processedNote` frame. The controller will call dispose() when it has
    // received the note (or after a hard timeout).
    await _levelsController?.close();
    _levelsController = null;
    await _byteCountController?.close();
    _byteCountController = null;
  }

  /// Hard-tear-down used when the user navigates away or after a connection
  /// failure. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    AppLogger.i('TranscriptionRepository.dispose()');

    try {
      await _audioSub?.cancel();
    } catch (_) {}
    _audioSub = null;

    await _audio.stop();
    await _socket.close();

    final levels = _levelsController;
    _levelsController = null;
    if (levels != null && !levels.isClosed) {
      await levels.close();
    }

    final bytes = _byteCountController;
    _byteCountController = null;
    if (bytes != null && !bytes.isClosed) {
      await bytes.close();
    }
  }
}

/// Pair of streams returned for a live session.
class TranscriptionSession {
  const TranscriptionSession({
    required this.events,
    required this.audioLevels,
    required this.audioBytes,
  });

  /// Server-pushed transcription / note events.
  final Stream<TranscriptionEvent> events;

  /// Microphone RMS amplitudes (0..1) emitted at ~10 Hz, used by the
  /// presentation layer to drive the live waveform visualizer.
  final Stream<double> audioLevels;

  /// Raw byte counts per emitted frame — used by the debug panel to compute
  /// the actual capture rate and detect sample-rate mismatches.
  final Stream<int> audioBytes;
}
