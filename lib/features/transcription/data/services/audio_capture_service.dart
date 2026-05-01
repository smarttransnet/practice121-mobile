import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:async';

import 'package:record/record.dart';

import '../../../../core/constants/audio_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';

/// A single audio frame ready to be sent over the wire to the backend.
/// [bytes] is always exactly [AudioConstants.bytesPerFrame] bytes of
/// signed 16-bit little-endian mono PCM at [AudioConstants.sampleRate] Hz.
class AudioFrame {
  const AudioFrame({required this.bytes, required this.rms});
  final Uint8List bytes;

  /// RMS amplitude on a 0..1 scale — drives the orb visualizer.
  final double rms;
}

// ── WAV header guard ─────────────────────────────────────────────────────────
// Some builds of the `record` plugin prepend a 44-byte RIFF header to the
// very first chunk delivered by startStream(). Detect and skip it.
const int _kWavHeaderSize = 44;
const int _kRiff0 = 0x52; // R
const int _kRiff1 = 0x49; // I
const int _kRiff2 = 0x46; // F
const int _kRiff3 = 0x46; // F

/// Captures microphone audio and emits 100 ms PCM-16 frames at 16 kHz.
///
/// Uses the `record` plugin's [AudioEncoder.pcm16bits] stream mode. DSP flags
/// (echoCancel, noiseSuppress, autoGain) are deliberately disabled because
/// hardware telephony-grade DSP at 16 kHz can introduce spectral artifacts on
/// some chipsets that corrupt Google STT output.
class AudioCaptureService {
  AudioCaptureService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  StreamSubscription<Uint8List>? _rawSub;
  StreamController<AudioFrame>? _frameController;

  // Byte accumulator — collects raw chunks until we have a full 100 ms frame.
  final BytesBuilder _accumulator = BytesBuilder();

  // Diagnostics
  int _captureChunks = 0;
  int _bytesReceived = 0;
  bool _firstChunk = true;
  DateTime? _captureStarted;
  Timer? _rateTicker;

  /// Begin capturing and return a stream of 16 kHz PCM-16 audio frames.
  /// Throws [AudioCaptureFailure] on permission denial or hardware error.
  Future<Stream<AudioFrame>> start() async {
    if (_frameController != null) {
      throw const AudioCaptureFailure('Audio capture already running');
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const AudioCaptureFailure('Microphone permission denied');
    }

    try {
      final rawStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: AudioConstants.sampleRate,
          numChannels: AudioConstants.channels,
          // Hardware DSP disabled: telephony-grade processing at 16 kHz
          // introduces periodic artifacts on some chipsets that confuse STT.
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
        ),
      );

      _frameController = StreamController<AudioFrame>.broadcast();
      _captureStarted = DateTime.now();
      _bytesReceived = 0;
      _captureChunks = 0;
      _firstChunk = true;
      _accumulator.clear();
      _startRateTicker();

      _rawSub = rawStream.listen(
        _onRawChunk,
        onError: (Object error, StackTrace stack) {
          AppLogger.e('AudioCaptureService stream error', error, stack);
          _frameController?.addError(
            AudioCaptureFailure('Audio stream error: $error'),
          );
        },
        onDone: () async {
          AppLogger.i('AudioCaptureService raw stream done');
          await _frameController?.close();
        },
        cancelOnError: false,
      );

      AppLogger.i(
        'AudioCaptureService started — '
        '${AudioConstants.sampleRate} Hz, mono PCM16, '
        '${AudioConstants.frameDurationMs} ms frames',
      );

      return _frameController!.stream;
    } catch (e, stack) {
      AppLogger.e('Failed to start AudioCaptureService', e, stack);
      await _safeStop();
      throw AudioCaptureFailure('Could not start microphone: $e');
    }
  }

  Future<void> stop() async {
    AppLogger.i('AudioCaptureService stopping...');
    await _safeStop();
  }

  Future<void> _safeStop() async {
    _stopRateTicker();

    try {
      await _rawSub?.cancel();
    } catch (_) {}
    _rawSub = null;

    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (e) {
      AppLogger.w('AudioCaptureService recorder.stop() threw: $e');
    }

    _accumulator.clear();

    final controller = _frameController;
    _frameController = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  // ── Rate-check ticker ────────────────────────────────────────────────────

  void _startRateTicker() {
    _rateTicker?.cancel();
    _rateTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = _captureStarted == null
          ? 1.0
          : DateTime.now()
                  .difference(_captureStarted!)
                  .inMilliseconds /
              1000.0;
      if (elapsed < 1) return;

      final actualBps = _bytesReceived / elapsed;
      const expectedBps = AudioConstants.expectedBytesPerSec;
      final ratio = actualBps / expectedBps;
      final warn = ratio < 0.88 || ratio > 1.12;
      final tag = warn ? '⚠ RATE MISMATCH' : '✓';

      AppLogger.d(
        'AudioCaptureService $tag — '
        '${actualBps.toStringAsFixed(0)} B/s '
        '(expected $expectedBps), ratio ${ratio.toStringAsFixed(2)}, '
        'chunks=$_captureChunks',
      );
    });
  }

  void _stopRateTicker() {
    _rateTicker?.cancel();
    _rateTicker = null;
  }

  // ── Raw-chunk handler ────────────────────────────────────────────────────

  void _onRawChunk(Uint8List chunk) {
    final controller = _frameController;
    if (controller == null || controller.isClosed) return;

    _captureChunks++;

    // WAV-header guard: strip the first 44 bytes if the plugin prepends RIFF.
    Uint8List safe = chunk;
    if (_firstChunk) {
      _firstChunk = false;
      if (chunk.length >= 4 &&
          chunk[0] == _kRiff0 &&
          chunk[1] == _kRiff1 &&
          chunk[2] == _kRiff2 &&
          chunk[3] == _kRiff3) {
        AppLogger.w(
          'AudioCaptureService: WAV header detected — stripping '
          '$_kWavHeaderSize bytes',
        );
        if (chunk.length <= _kWavHeaderSize) return;
        safe = Uint8List.sublistView(chunk, _kWavHeaderSize);
      }
      final hex = safe
          .take(16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      AppLogger.d('AudioCaptureService: first 16 bytes: $hex');
    }

    _bytesReceived += safe.length;
    _accumulator.add(safe);

    while (_accumulator.length >= AudioConstants.bytesPerFrame) {
      final all = _accumulator.takeBytes();
      var offset = 0;

      while (all.length - offset >= AudioConstants.bytesPerFrame) {
        final frameBytes = Uint8List.fromList(
          all.sublist(offset, offset + AudioConstants.bytesPerFrame),
        );
        offset += AudioConstants.bytesPerFrame;

        controller.add(
          AudioFrame(bytes: frameBytes, rms: _computeRms(frameBytes)),
        );
      }

      if (offset < all.length) {
        _accumulator.add(all.sublist(offset));
      }
    }
  }

  // ── RMS ──────────────────────────────────────────────────────────────────

  static double _computeRms(Uint8List frame) {
    final view = ByteData.sublistView(frame);
    final sampleCount = frame.length ~/ 2;
    if (sampleCount == 0) return 0;

    double sumSq = 0;
    for (var i = 0; i < sampleCount; i++) {
      final s = view.getInt16(i * 2, Endian.little);
      final n = s / 32768.0;
      sumSq += n * n;
    }
    return math.sqrt(sumSq / sampleCount);
  }
}
