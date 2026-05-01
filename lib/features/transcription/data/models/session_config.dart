import 'dart:convert';

/// Configuration sent as the FIRST text frame on the WebSocket — must match the
/// shape `TranscriptionWebSocketHandler.HandleAsync` expects:
///   { "prompt"?: string, "model"?: string }
class SessionConfig {
  const SessionConfig({
    this.customPrompt,
    this.modelName,
  });

  /// Optional custom Gemini system prompt (overrides backend default).
  final String? customPrompt;

  /// Optional Gemini model name (e.g. "gemini-2.5-flash").
  final String? modelName;

  static const empty = SessionConfig();

  SessionConfig copyWith({
    String? customPrompt,
    String? modelName,
  }) =>
      SessionConfig(
        customPrompt: customPrompt ?? this.customPrompt,
        modelName: modelName ?? this.modelName,
      );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    final prompt = customPrompt?.trim();
    final model = modelName?.trim();
    if (prompt != null && prompt.isNotEmpty) {
      map['prompt'] = prompt;
    }
    if (model != null && model.isNotEmpty) {
      map['model'] = model;
    }
    return map;
  }

  String encode() => jsonEncode(toJson());
}
