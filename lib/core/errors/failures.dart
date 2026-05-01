/// Domain-level failure types.
///
/// Using sealed-style error objects (rather than throwing raw `Exception`)
/// keeps the controllers' error-handling code exhaustive and self-documenting.
abstract class Failure implements Exception {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// Microphone permission was denied (or permanently denied) by the user.
class MicrophonePermissionFailure extends Failure {
  const MicrophonePermissionFailure({this.permanentlyDenied = false})
      : super('Microphone permission denied');

  final bool permanentlyDenied;
}

/// The backend WebSocket either could not be reached or dropped mid-session
/// after exhausting all retry attempts.
class TranscriptionConnectionFailure extends Failure {
  const TranscriptionConnectionFailure(super.message);
}

/// Anything from the audio recorder (device busy, hardware not available,
/// unsupported sample rate, etc.).
class AudioCaptureFailure extends Failure {
  const AudioCaptureFailure(super.message);
}

/// Unknown / wrapping failure for unexpected exceptions.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}
