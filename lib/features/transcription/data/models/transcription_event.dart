/// Strongly-typed model for the JSON payloads streamed by the backend
/// WebSocket. Matches `TranscriptionResult` in `Backend5/Services/SpeechService.cs`.
///
/// During an active session the server sends interim and final transcripts.
/// At the end of the session it sends a single payload with both
/// `processedNote` (the Gemini-generated clinical note) and `fullTranscript`.
class TranscriptionEvent {
  const TranscriptionEvent({
    required this.transcript,
    required this.isFinal,
    this.confidence = 0,
    this.speakerLabel = '',
    this.processedNote,
    this.fullTranscript,
  });

  final String transcript;
  final bool isFinal;
  final double confidence;
  final String speakerLabel;

  /// Set ONLY on the very last frame — Gemini's clinical note. `null` for all
  /// live transcription frames.
  final String? processedNote;

  /// Set with `processedNote` — the verbatim concatenated transcript. `null`
  /// for live frames.
  final String? fullTranscript;

  /// True when this frame carries the final Gemini note + raw transcript and
  /// the session can be considered complete.
  bool get isClinicalNote =>
      processedNote != null && processedNote!.isNotEmpty;

  factory TranscriptionEvent.fromJson(Map<String, dynamic> json) {
    return TranscriptionEvent(
      transcript: (json['transcript'] as String?) ?? '',
      isFinal: (json['isFinal'] as bool?) ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      speakerLabel: (json['speakerLabel'] as String?) ?? '',
      processedNote: json['processedNote'] as String?,
      fullTranscript: json['fullTranscript'] as String?,
    );
  }
}

/// A finalized utterance to display in the live transcript view.
class FinalUtterance {
  const FinalUtterance({
    required this.text,
    required this.speakerLabel,
    required this.confidence,
    required this.timestamp,
  });

  final String text;
  final String speakerLabel;
  final double confidence;
  final DateTime timestamp;
}
