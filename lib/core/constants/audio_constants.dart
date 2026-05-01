/// Audio capture constants required by the backend STT pipeline.
///
/// The .NET backend (see `SpeechService.cs`) hard-codes Google STT v2 with:
///   • encoding         = LINEAR16 (signed 16-bit little-endian PCM)
///   • sample rate      = 16 000 Hz
///   • channels         = 1 (mono)
///   • per-frame target = ≤100 ms (server splits to 100 ms slices internally)
class AudioConstants {
  const AudioConstants._();

  /// Sample rate requested from and sent to the backend (Hz).
  static const int sampleRate = 16000;

  /// Mono.
  static const int channels = 1;

  /// 16-bit signed little-endian PCM = 2 bytes per sample.
  static const int bytesPerSample = 2;

  /// One frame = 100 ms of audio.
  static const int frameDurationMs = 100;

  /// Number of audio samples per 100 ms frame.
  /// 16 000 Hz × 0.1 s = 1 600 samples.
  static const int samplesPerFrame = sampleRate * frameDurationMs ~/ 1000;

  /// Number of bytes per 100 ms frame sent to the backend.
  /// 1 600 samples × 2 bytes = 3 200 bytes.
  static const int bytesPerFrame = samplesPerFrame * bytesPerSample;

  /// Expected bytes per second at this rate. Used by the debug panel.
  static const int expectedBytesPerSec = sampleRate * bytesPerSample;

  /// Number of bars rendered in the live audio waveform visualizer.
  static const int visualizerBarCount = 24;
}
