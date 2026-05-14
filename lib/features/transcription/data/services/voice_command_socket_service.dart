import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';

class VoiceCommandEvent {
  const VoiceCommandEvent({
    this.transcript = '',
    this.isFinal = false,
    this.fullCommand,
  });

  final String transcript;
  final bool isFinal;
  final String? fullCommand;

  factory VoiceCommandEvent.fromJson(Map<String, dynamic> json) {
    return VoiceCommandEvent(
      transcript: json['transcript'] as String? ?? '',
      isFinal: json['isFinal'] as bool? ?? false,
      fullCommand: json['fullCommand'] as String?,
    );
  }
}

class VoiceCommandSocketService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  StreamController<VoiceCommandEvent>? _eventController;

  Future<Stream<VoiceCommandEvent>> connect({required Uri url}) async {
    if (_channel != null) {
      throw const TranscriptionConnectionFailure('Voice command socket already connected');
    }

    try {
      AppLogger.i('Connecting to voice command WS: $url');
      final channel = WebSocketChannel.connect(url);
      await channel.ready;

      _channel = channel;
      _eventController = StreamController<VoiceCommandEvent>.broadcast();

      _channelSub = channel.stream.listen(
        _onMessage,
        onError: (Object error, StackTrace stack) {
          AppLogger.e('Voice command WS error', error, stack);
          _eventController?.addError(
            TranscriptionConnectionFailure('WebSocket error: $error'),
          );
        },
        onDone: () async {
          AppLogger.i('Voice command WS closed');
          await _eventController?.close();
        },
        cancelOnError: false,
      );

      return _eventController!.stream;
    } catch (e, stack) {
      AppLogger.e('Failed to open voice command WS', e, stack);
      await _safeClose();
      throw TranscriptionConnectionFailure('Could not connect: $e');
    }
  }

  void sendAudioFrame(Uint8List bytes) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(bytes);
    } catch (e) {
      AppLogger.w('sendAudioFrame failed: $e');
    }
  }

  Future<void> sendStop() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add('STOP');
      AppLogger.i('Sent STOP to voice command WS');
    } catch (e) {
      AppLogger.w('sendStop failed: $e');
    }
  }

  Future<void> close() async {
    AppLogger.i('Voice command WS close()');
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
      if (json is! Map<String, dynamic>) return;
      controller.add(VoiceCommandEvent.fromJson(json));
    } catch (e, stack) {
      AppLogger.w('Failed to parse WS payload: $e', e, stack);
    }
  }
}
