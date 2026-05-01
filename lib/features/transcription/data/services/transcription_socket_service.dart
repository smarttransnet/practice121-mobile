import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../models/session_config.dart';
import '../models/transcription_event.dart';

/// WebSocket protocol client for `/ws/transcribe`.
///
/// The wire format is identical to the React frontend's:
///   1. Client opens the WS connection.
///   2. Client sends ONE text frame: a JSON config (`SessionConfig`).
///   3. Client streams binary PCM-16 audio frames (≤100 ms each).
///   4. Client sends the text frame `"STOP"` to request a final note.
///   5. Server streams interim/final transcripts as JSON text frames.
///   6. Server sends one final JSON frame with `processedNote` + `fullTranscript`.
///   7. Server closes the socket.
class TranscriptionSocketService {
  TranscriptionSocketService();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  StreamController<TranscriptionEvent>? _eventController;

  /// Open a connection and configure the session.
  ///
  /// Throws [TranscriptionConnectionFailure] if the server cannot be reached.
  Future<Stream<TranscriptionEvent>> connect({
    required Uri url,
    required SessionConfig config,
  }) async {
    if (_channel != null) {
      throw const TranscriptionConnectionFailure(
        'Transcription socket already connected',
      );
    }

    try {
      AppLogger.i('Connecting to transcription WS: $url');
      final channel = WebSocketChannel.connect(url);
      // ready is the canonical "connection established" signal in
      // web_socket_channel ^3.x.
      await channel.ready;

      _channel = channel;
      _eventController = StreamController<TranscriptionEvent>.broadcast();

      _channelSub = channel.stream.listen(
        _onMessage,
        onError: (Object error, StackTrace stack) {
          AppLogger.e('Transcription WS error', error, stack);
          _eventController?.addError(
            TranscriptionConnectionFailure('WebSocket error: $error'),
          );
        },
        onDone: () async {
          AppLogger.i(
            'Transcription WS closed (code=${channel.closeCode}, reason=${channel.closeReason})',
          );
          await _eventController?.close();
        },
        cancelOnError: false,
      );

      // First text frame MUST be the session config — see backend
      // `TranscriptionWebSocketHandler.HandleAsync`.
      channel.sink.add(config.encode());
      AppLogger.d('Sent session config: ${config.encode()}');

      return _eventController!.stream;
    } catch (e, stack) {
      AppLogger.e('Failed to open transcription WS', e, stack);
      await _safeClose();
      throw TranscriptionConnectionFailure('Could not connect: $e');
    }
  }

  /// Send a single PCM-16 binary audio frame.
  void sendAudioFrame(Uint8List bytes) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(bytes);
    } catch (e) {
      AppLogger.w('sendAudioFrame failed: $e');
    }
  }

  /// Tell the server to stop streaming and run Gemini. The server will
  /// respond with a final `processedNote` payload before closing.
  Future<void> sendStop() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add('STOP');
      AppLogger.i('Sent STOP to transcription WS');
    } catch (e) {
      AppLogger.w('sendStop failed: $e');
    }
  }

  /// Close the connection. Idempotent.
  Future<void> close() async {
    AppLogger.i('Transcription WS close()');
    await _safeClose();
  }

  Future<void> _safeClose() async {
    try {
      await _channelSub?.cancel();
    } catch (_) {}
    _channelSub = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    final controller = _eventController;
    _eventController = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  void _onMessage(dynamic raw) {
    final controller = _eventController;
    if (controller == null || controller.isClosed) return;

    try {
      final str = raw is String ? raw : utf8.decode(raw as List<int>);
      final json = jsonDecode(str);
      if (json is! Map<String, dynamic>) {
        AppLogger.w('Unexpected WS payload (not a JSON object): $str');
        return;
      }
      controller.add(TranscriptionEvent.fromJson(json));
    } catch (e, stack) {
      AppLogger.w('Failed to parse WS payload: $e', e, stack);
    }
  }
}
