import '../../../../core/constants/audio_constants.dart';
import '../../data/models/session_config.dart';
import '../../data/models/transcription_event.dart';
import '../../data/services/queue_service.dart';

/// High-level lifecycle of a transcription session.
///
/// `idle`             - Nothing happening. Mic is the prominent CTA.
/// `connecting`       - Opening WS / requesting mic. Show spinner on the mic button.
/// `recording`        - Live: streaming audio, receiving interim/final transcripts.
/// `processing`       - User pressed Stop. Server is running Gemini. Show shimmer.
/// `noteReady`        - Final clinical note has arrived. Show the note panel.
/// `error`            - Last action failed. Surface a recoverable error message.
/// `commandRecording` - User is speaking an amendment command (Talk to Edit).
/// `amending`         - Sending amendment request to the server.
enum SessionStatus {
  idle,
  connecting,
  recording,
  processing,
  noteReady,
  error,
  commandRecording,
  amending,
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
    this.amendmentCommand = '',
    this.originalProcessedNote,
    this.amendmentHistory = const [],
    this.isSendingEmail = false,
    this.isAdvancingQueue = false,
    this.activePatient,
  });

  final SessionStatus status;

  /// Committed utterances from STT, in chronological order.
  final List<FinalUtterance> finals;

  /// The current uncommitted interim transcript (replaced as the user speaks).
  final String interim;

  /// The Gemini-generated SOAP-style clinical note (only set after Stop).
  final String? processedNote;

  /// The very first version of the processedNote before any amendments.
  final String? originalProcessedNote;

  /// List of all amendment commands applied in this session.
  final List<String> amendmentHistory;

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

  /// The transcribed text of the voice command for amendment.
  final String amendmentCommand;

  /// Whether an email is currently being sent.
  final bool isSendingEmail;

  /// Whether the queue advance (New Session) call is in-flight.
  final bool isAdvancingQueue;

  /// The patient currently IN CONSULTATION after a successful queue advance.
  /// Null when no advance has been performed yet or the queue was empty.
  final QueuePatient? activePatient;

  bool get isRecording => status == SessionStatus.recording;
  bool get isCommandRecording => status == SessionStatus.commandRecording;
  bool get isAmending => status == SessionStatus.amending;

  bool get isBusy =>
      status == SessionStatus.connecting ||
      status == SessionStatus.processing ||
      status == SessionStatus.amending;

  bool get hasNote =>
      (status == SessionStatus.noteReady || status == SessionStatus.amending || status == SessionStatus.commandRecording) &&
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
    String? amendmentCommand,
    bool clearAmendmentCommand = false,
    String? originalProcessedNote,
    List<String>? amendmentHistory,
    bool? isSendingEmail,
    bool? isAdvancingQueue,
    QueuePatient? activePatient,
    bool clearActivePatient = false,
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
      amendmentCommand: clearAmendmentCommand
          ? ''
          : (amendmentCommand ?? this.amendmentCommand),
      originalProcessedNote: clearProcessedNote
          ? null
          : (originalProcessedNote ?? this.originalProcessedNote),
      amendmentHistory:
          clearProcessedNote ? const [] : (amendmentHistory ?? this.amendmentHistory),
      isSendingEmail: isSendingEmail ?? this.isSendingEmail,
      isAdvancingQueue: isAdvancingQueue ?? this.isAdvancingQueue,
      activePatient: clearActivePatient
          ? null
          : (activePatient ?? this.activePatient),
    );
  }
}
