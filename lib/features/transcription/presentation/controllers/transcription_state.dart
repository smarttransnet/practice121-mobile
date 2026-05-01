import '../../../../core/constants/audio_constants.dart';
import '../../data/models/session_config.dart';
import '../../data/models/transcription_event.dart';

/// High-level lifecycle of a transcription session.
///
/// `idle`        - Nothing happening. Mic is the prominent CTA.
/// `connecting`  - Opening WS / requesting mic. Show spinner on the mic button.
/// `recording`   - Live: streaming audio, receiving interim/final transcripts.
/// `processing`  - User pressed Stop. Server is running Gemini. Show shimmer.
/// `noteReady`   - Final clinical note has arrived. Show the note panel.
/// `error`       - Last action failed. Surface a recoverable error message.
enum SessionStatus {
  idle,
  connecting,
  recording,
  processing,
  noteReady,
  error,
}

class TranscriptionState {
  const TranscriptionState({
    this.status = SessionStatus.idle,
    this.finals = const [],
    this.interim = '',
    this.processedNote,
    this.fullTranscript,
    this.errorMessage,
    this.config = SessionConfig.empty,
    this.audioLevels = const [],
    this.recordingStartedAt,
    this.totalBytesReceived = 0,
  });

  final SessionStatus status;

  /// Committed utterances from STT, in chronological order.
  final List<FinalUtterance> finals;

  /// The current uncommitted interim transcript (replaced as the user speaks).
  final String interim;

  /// The Gemini-generated SOAP-style clinical note (only set after Stop).
  final String? processedNote;

  /// Verbatim concatenated transcript (only set after Stop).
  final String? fullTranscript;

  /// User-visible error string. Cleared automatically on the next start.
  final String? errorMessage;

  /// Configuration that will be sent on the next session start.
  final SessionConfig config;

  /// Rolling buffer of recent RMS amplitudes for the visualizer
  /// (length == [AudioConstants.visualizerBarCount]).
  final List<double> audioLevels;

  /// Wall-clock at which the current recording started, or null when idle.
  /// Used to render the elapsed-time chip.
  final DateTime? recordingStartedAt;

  /// Cumulative bytes received from the mic for the current session.
  /// Used in the debug panel to display actual vs expected data rate.
  final int totalBytesReceived;

  bool get isRecording => status == SessionStatus.recording;
  bool get isBusy =>
      status == SessionStatus.connecting ||
      status == SessionStatus.processing;
  bool get hasNote =>
      status == SessionStatus.noteReady &&
      (processedNote?.isNotEmpty ?? false);

  /// Most recent amplitude on a 0..1 scale (clamped). Drives the orb.
  double get currentAmplitude {
    if (audioLevels.isEmpty) return 0;
    final v = audioLevels.last;
    if (v.isNaN || v < 0) return 0;
    return v > 1 ? 1 : v;
  }

  Duration? get recordingElapsed {
    final start = recordingStartedAt;
    if (start == null) return null;
    return DateTime.now().difference(start);
  }

  /// Actual audio bytes per second, or null when not recording.
  /// Expected value: 16000 Hz × 2 bytes = 32 000 B/s.
  double? get audioBytesPerSecond {
    final elapsed = recordingElapsed;
    if (elapsed == null || elapsed.inMilliseconds < 500) return null;
    return totalBytesReceived / (elapsed.inMilliseconds / 1000.0);
  }

  TranscriptionState copyWith({
    SessionStatus? status,
    List<FinalUtterance>? finals,
    String? interim,
    String? processedNote,
    bool clearProcessedNote = false,
    String? fullTranscript,
    bool clearFullTranscript = false,
    String? errorMessage,
    bool clearError = false,
    SessionConfig? config,
    List<double>? audioLevels,
    DateTime? recordingStartedAt,
    bool clearRecordingStartedAt = false,
    int? totalBytesReceived,
  }) {
    return TranscriptionState(
      status: status ?? this.status,
      finals: finals ?? this.finals,
      interim: interim ?? this.interim,
      processedNote:
          clearProcessedNote ? null : (processedNote ?? this.processedNote),
      fullTranscript:
          clearFullTranscript ? null : (fullTranscript ?? this.fullTranscript),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      config: config ?? this.config,
      audioLevels: audioLevels ?? this.audioLevels,
      recordingStartedAt: clearRecordingStartedAt
          ? null
          : (recordingStartedAt ?? this.recordingStartedAt),
      totalBytesReceived:
          totalBytesReceived ?? this.totalBytesReceived,
    );
  }
}
