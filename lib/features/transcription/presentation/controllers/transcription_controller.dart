import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/constants/audio_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../data/models/transcription_event.dart';
import '../../data/repositories/transcription_repository.dart';
import '../../data/services/audio_capture_service.dart';
import '../../data/services/transcription_socket_service.dart';
import 'transcription_state.dart';

// ────────────────────────────────────────────────────────────────────────────
// Providers (DI graph)
// ────────────────────────────────────────────────────────────────────────────

/// Top-level app config. Override in tests / dev with `ProviderScope.overrides`.
final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return const PermissionService();
});

/// Repository factory — fresh instance per session so old subscriptions can't
/// leak into a new recording.
final transcriptionRepositoryFactoryProvider =
    Provider<TranscriptionRepository Function()>((ref) {
  final config = ref.watch(appConfigProvider);
  return () => TranscriptionRepository(
        appConfig: config,
        audioCaptureService: AudioCaptureService(),
        socketService: TranscriptionSocketService(),
      );
});

final transcriptionControllerProvider =
    StateNotifierProvider<TranscriptionController, TranscriptionState>((ref) {
  return TranscriptionController(
    permissionService: ref.read(permissionServiceProvider),
    repositoryFactory: ref.read(transcriptionRepositoryFactoryProvider),
  );
});

// ────────────────────────────────────────────────────────────────────────────
// Controller
// ────────────────────────────────────────────────────────────────────────────

class TranscriptionController extends StateNotifier<TranscriptionState> {
  TranscriptionController({
    required PermissionService permissionService,
    required TranscriptionRepository Function() repositoryFactory,
  })  : _permissionService = permissionService,
        _repositoryFactory = repositoryFactory,
        super(const TranscriptionState());

  final PermissionService _permissionService;
  final TranscriptionRepository Function() _repositoryFactory;

  TranscriptionRepository? _activeRepository;
  StreamSubscription<TranscriptionEvent>? _eventSub;
  StreamSubscription<double>? _levelsSub;
  StreamSubscription<int>? _bytesSub;
  Timer? _processingWatchdog;

  /// Monotonic id incremented every `start()`. Captured by every event
  /// handler so callbacks fired from a previous session's still-alive stream
  /// (e.g. a straggler frame arriving while the WS is closing) cannot mutate
  /// the current session's state. This is the safety net behind the
  /// "previous session bleeding into new session" bug.
  int _sessionEpoch = 0;

  /// Wall-clock at which the current recording started — drives the timer.
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;

  /// User-facing message produced when the user stops the session and waits
  /// for Gemini.
  static const _processingTimeout = Duration(minutes: 5);

  /// Update the prompt that will be sent on the next start.
  void updatePrompt(String? prompt) {
    state = state.copyWith(
      config: state.config.copyWith(customPrompt: prompt),
    );
  }

  /// Update the model that will be sent on the next start.
  void updateModel(String? model) {
    state = state.copyWith(
      config: state.config.copyWith(modelName: model),
    );
  }

  /// Toggle recording. Single entry point used by the mic button.
  Future<void> toggleRecording() async {
    if (state.isBusy) return;
    if (state.isRecording) {
      await stop();
    } else {
      await start();
    }
  }

  /// Begin a new session.
  Future<void> start() async {
    if (state.status == SessionStatus.recording ||
        state.status == SessionStatus.connecting) {
      return;
    }

    AppLogger.i('TranscriptionController.start()');

    // ── CRITICAL: drain the previous session synchronously ────────────────
    // The previous session may have scheduled a microtask to dispose its
    // repo (see _onEvent for the clinical-note path). If the user taps the
    // mic again before that microtask runs, the old WS subscription is
    // still alive and any in-flight frame would corrupt the new state.
    // Await the teardown here so we always start from a clean slate.
    await _disposeActiveRepository();

    // Bump the epoch so any callback that DOES sneak through from the
    // previous session (e.g. an event already on the microtask queue) is
    // ignored at handler entry.
    final epoch = ++_sessionEpoch;

    state = state.copyWith(
      status: SessionStatus.connecting,
      finals: const [],
      interim: '',
      clearProcessedNote: true,
      clearFullTranscript: true,
      clearError: true,
      audioLevels: List<double>.filled(
        AudioConstants.visualizerBarCount,
        0,
      ),
      recordingStartedAt: null,
      clearRecordingStartedAt: true,
    );

    // ── Microphone permission ────────────────────────────────────────────
    final permission = await _permissionService.ensureMicrophone();
    if (permission != MicPermissionResult.granted) {
      _failWith(
        permission == MicPermissionResult.permanentlyDenied
            ? 'Microphone access is permanently denied. Please enable it in Settings to record.'
            : 'Microphone permission is required to record.',
      );
      return;
    }

    // Bail if a competing call has superseded us during the await.
    if (epoch != _sessionEpoch) {
      AppLogger.w('start() superseded during permission request');
      return;
    }

    // ── Open repository (WS + mic) ───────────────────────────────────────
    final repo = _repositoryFactory();
    _activeRepository = repo;

    try {
      final session = await repo.startSession(config: state.config);

      if (epoch != _sessionEpoch) {
        // Another start/stop happened while we were connecting; throw away
        // this session immediately.
        AppLogger.w('start() superseded during socket connect');
        await repo.dispose();
        return;
      }

      _eventSub = session.events.listen(
        (event) => _onEvent(event, epoch),
        onError: (Object e, StackTrace s) => _onEventError(e, s, epoch),
        onDone: () => _onEventDone(epoch),
      );

      _levelsSub = session.audioLevels.listen(
        (rms) => _onAudioLevel(rms, epoch),
        onError: (_) {/* swallowed; visualizer just stops updating */},
      );

      _bytesSub = session.audioBytes.listen(
        (bytes) => _onAudioBytes(bytes, epoch),
        onError: (_) {},
      );

      _recordingStartedAt = DateTime.now();
      _startRecordingTicker();

      state = state.copyWith(
        status: SessionStatus.recording,
        recordingStartedAt: _recordingStartedAt,
        totalBytesReceived: 0,
      );
      AppLogger.i('Session live (epoch=$epoch)');
    } on Failure catch (f) {
      AppLogger.e('Session start failed', f);
      await _disposeActiveRepository();
      _failWith(f.message);
    } catch (e, stack) {
      AppLogger.e('Session start failed (unexpected)', e, stack);
      await _disposeActiveRepository();
      _failWith('Could not start session: $e');
    }
  }

  /// User pressed Stop — wait for the Gemini note to come back.
  Future<void> stop() async {
    if (state.status != SessionStatus.recording) return;

    AppLogger.i('TranscriptionController.stop()');
    _stopRecordingTicker();

    state = state.copyWith(
      status: SessionStatus.processing,
      audioLevels: List<double>.filled(
        AudioConstants.visualizerBarCount,
        0,
      ),
    );

    // Stop sending audio but keep listening for the final note.
    try {
      await _activeRepository?.stopSession();
    } catch (e) {
      AppLogger.w('stopSession() threw: $e');
    }

    // If the server never returns a note (network drop, error) clear up
    // gracefully after a generous deadline.
    _processingWatchdog?.cancel();
    _processingWatchdog = Timer(_processingTimeout, () {
      if (state.status == SessionStatus.processing) {
        AppLogger.w('Gemini note never arrived — timing out the session');
        _failWith(
          'The server is taking too long to generate the clinical note. '
          'Please try again.',
        );
      }
    });
  }

  /// Reset to idle (used after dismissing an error, or after the user
  /// closes the clinical note panel).
  void reset() {
    AppLogger.i('TranscriptionController.reset()');
    _sessionEpoch++;
    _stopRecordingTicker();
    state = const TranscriptionState();
  }

  // ── Event handlers ─────────────────────────────────────────────────────

  void _onEvent(TranscriptionEvent event, int epoch) {
    if (epoch != _sessionEpoch) {
      AppLogger.d('Dropping event from stale epoch $epoch (current=$_sessionEpoch)');
      return;
    }

    if (event.isClinicalNote) {
      AppLogger.i(
        'Received final clinical note (${event.processedNote!.length} chars)',
      );
      _processingWatchdog?.cancel();
      _processingWatchdog = null;

      state = state.copyWith(
        status: SessionStatus.noteReady,
        processedNote: event.processedNote,
        fullTranscript: event.fullTranscript,
        interim: '',
      );
      // Tear down WS / mic — server will close anyway.
      // Do it on a microtask so the state update is observed first.
      Future.microtask(_disposeActiveRepository);
      return;
    }

    if (event.isFinal) {
      final newFinals = List<FinalUtterance>.from(state.finals)
        ..add(FinalUtterance(
          text: event.transcript.trim(),
          speakerLabel: event.speakerLabel,
          confidence: event.confidence,
          timestamp: DateTime.now(),
        ));
      state = state.copyWith(
        finals: newFinals,
        interim: '',
      );
    } else {
      state = state.copyWith(interim: event.transcript);
    }
  }

  void _onEventError(Object error, StackTrace stack, int epoch) {
    if (epoch != _sessionEpoch) return;
    AppLogger.e('WS event stream error', error, stack);
    final message =
        error is Failure ? error.message : 'Connection error: $error';
    _failWith(message);
  }

  void _onEventDone(int epoch) {
    if (epoch != _sessionEpoch) return;
    AppLogger.i('WS event stream closed');
    if (state.status == SessionStatus.processing) {
      _failWith(
        'The session ended before a clinical note was generated. '
        'Please try again.',
      );
    } else if (state.status == SessionStatus.recording) {
      _failWith('Connection to the server was lost. Please try again.');
    }
  }

  void _onAudioLevel(double rms, int epoch) {
    if (epoch != _sessionEpoch) return;
    final levels = List<double>.from(state.audioLevels);
    if (levels.length >= AudioConstants.visualizerBarCount) {
      levels.removeAt(0);
    }
    levels.add(rms);
    state = state.copyWith(audioLevels: levels);
  }

  void _onAudioBytes(int byteCount, int epoch) {
    if (epoch != _sessionEpoch) return;
    state = state.copyWith(
      totalBytesReceived: state.totalBytesReceived + byteCount,
    );
  }

  // ── Recording timer ────────────────────────────────────────────────────

  void _startRecordingTicker() {
    _recordingTicker?.cancel();
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      // Trigger a state rebuild so consumers reading `recordingElapsed`
      // refresh once a second. We don't store the elapsed value because
      // it's trivially derived from `recordingStartedAt` when needed.
      if (state.status == SessionStatus.recording) {
        state = state.copyWith(); // no-op copy — bumps listeners
      }
    });
  }

  void _stopRecordingTicker() {
    _recordingTicker?.cancel();
    _recordingTicker = null;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  void _failWith(String message) {
    _processingWatchdog?.cancel();
    _processingWatchdog = null;
    _stopRecordingTicker();
    state = state.copyWith(
      status: SessionStatus.error,
      errorMessage: message,
      audioLevels: List<double>.filled(
        AudioConstants.visualizerBarCount,
        0,
      ),
    );
    Future.microtask(_disposeActiveRepository);
  }

  Future<void> _disposeActiveRepository() async {
    final repo = _activeRepository;
    _activeRepository = null;

    try {
      await _eventSub?.cancel();
    } catch (_) {}
    _eventSub = null;

    try {
      await _levelsSub?.cancel();
    } catch (_) {}
    _levelsSub = null;

    try {
      await _bytesSub?.cancel();
    } catch (_) {}
    _bytesSub = null;

    if (repo != null) {
      try {
        await repo.dispose();
      } catch (e) {
        AppLogger.w('Repository dispose failed: $e');
      }
    }
  }

  /// Dismiss any showing error and return to idle.
  void dismissError() {
    if (state.status == SessionStatus.error) {
      state = state.copyWith(
        status: SessionStatus.idle,
        clearError: true,
      );
    }
  }

  @override
  void dispose() {
    _processingWatchdog?.cancel();
    _processingWatchdog = null;
    _stopRecordingTicker();
    _disposeActiveRepository();
    super.dispose();
  }
}
