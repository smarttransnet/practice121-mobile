import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/constants/audio_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../data/models/transcription_event.dart';
import '../../data/repositories/transcription_repository.dart';
import '../../data/services/audio_capture_service.dart';
import '../../data/services/note_amend_service.dart';
import '../../data/services/note_email_service.dart';
import '../../data/services/queue_service.dart';
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

final noteAmendServiceProvider = Provider<NoteAmendService>((ref) {
  return NoteAmendService();
});

final noteEmailServiceProvider = Provider<NoteEmailService>((ref) {
  return NoteEmailService();
});

final queueServiceProvider = Provider<QueueService>((ref) {
  return QueueService();
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
    amendService: ref.read(noteAmendServiceProvider),
    sendGridService: ref.read(noteEmailServiceProvider),
    queueService: ref.read(queueServiceProvider),
    config: ref.read(appConfigProvider),
  );
});

// ────────────────────────────────────────────────────────────────────────────
// Controller
// ────────────────────────────────────────────────────────────────────────────

class TranscriptionController extends StateNotifier<TranscriptionState> with WidgetsBindingObserver {
  TranscriptionController({
    required PermissionService permissionService,
    required TranscriptionRepository Function() repositoryFactory,
    required NoteAmendService amendService,
    required NoteEmailService sendGridService,
    required QueueService queueService,
    required AppConfig config,
  })  : _permissionService = permissionService,
        _repositoryFactory = repositoryFactory,
        _amendService = amendService,
        _emailService = sendGridService,
        _queueService = queueService,
        _config = config,
        super(const TranscriptionState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  // ── Wake lock helpers ───────────────────────────────────────────────────
  Future<void> _enableWakeLock() async {
    try {
      await WakelockPlus.enable(); // Screen wake: enabled
      AppLogger.i('Screen wake lock enabled');
    } catch (e) {
      AppLogger.w('Failed to enable screen wake lock: $e');
    }
  }

  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable(); // Screen wake: disabled
      AppLogger.i('Screen wake lock disabled');
    } catch (e) {
      AppLogger.w('Failed to disable screen wake lock: $e');
    }
  }

  // ── Lifecycle states ─────────────────────────────────────────────────────
  DateTime? _pausedAt;
  bool _wasRecordingBeforePause = false;
  bool _wasCommandBeforePause = false;

  bool get _isCurrentlyRecording =>
      state.status == SessionStatus.recording ||
      state.status == SessionStatus.commandRecording;

  final PermissionService _permissionService;
  final TranscriptionRepository Function() _repositoryFactory;
  final NoteAmendService _amendService;
  final NoteEmailService _emailService;
  final QueueService _queueService;
  final AppConfig _config;

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

  /// Start a voice-command recording session for amendment.
  Future<void> startCommand() async {
    if (state.isBusy || state.isRecording) return;

    AppLogger.i('TranscriptionController.startCommand()');
    await _disposeActiveRepository();
    final epoch = ++_sessionEpoch;

    state = state.copyWith(
      status: SessionStatus.commandRecording,
      amendmentCommand: '',
      clearAmendmentCommand: true,
      audioLevels: List<double>.filled(AudioConstants.visualizerBarCount, 0),
    );

    final permission = await _permissionService.ensureMicrophone();
    if (permission != MicPermissionResult.granted) {
      _failWith('Microphone permission is required to record commands.');
      return;
    }
    if (epoch != _sessionEpoch) return;

    final repo = _repositoryFactory();
    _activeRepository = repo;

    try {
      final session = await repo.startSession(isCommand: true);
      if (epoch != _sessionEpoch) {
        await repo.dispose();
        return;
      }

      _eventSub = session.events.listen(
        (event) {
          if (epoch != _sessionEpoch) return;
          if (event.transcript.isNotEmpty) {
            state = state.copyWith(amendmentCommand: event.transcript);
          }
        },
        onError: (e, s) => _onEventError(e, s, epoch),
        onDone: () => _onEventDone(epoch),
      );

      _levelsSub = session.audioLevels.listen(
        (rms) => _onAudioLevel(rms, epoch),
      );

      _recordingStartedAt = DateTime.now();
      _startRecordingTicker();
      await _enableWakeLock();

      state = state.copyWith(recordingStartedAt: _recordingStartedAt);
    } catch (e) {
      _failWith('Could not start command session: $e');
    }
  }

  /// Stop voice-command recording and trigger amendment.
  Future<void> stopCommand() async {
    if (state.status != SessionStatus.commandRecording) return;

    final command = state.amendmentCommand;
    AppLogger.i('TranscriptionController.stopCommand() command: $command');

    _stopRecordingTicker();
    await _disableWakeLock();
    await _disposeActiveRepository();

    if (command.trim().isEmpty) {
      state = state.copyWith(status: SessionStatus.noteReady);
      return;
    }

    await amendNote(command);
  }

  /// Send a text or voice command to Gemini to amend the current note.
  Future<void> amendNote(String command) async {
    if (state.processedNote == null) return;

    AppLogger.i('TranscriptionController.amendNote() command: $command');

    state = state.copyWith(
      status: SessionStatus.amending,
      clearError: true,
    );

    try {
      final amended = await _amendService.amendClinicalNote(
        url: Uri.parse(_config.amendUrl),
        originalNote: state.processedNote!,
        command: command,
        modelName: state.config.modelName,
      );

      state = state.copyWith(
        status: SessionStatus.noteReady,
        processedNote: amended,
        amendmentHistory: [...state.amendmentHistory, command],
        clearError: true,
      );
    } on Failure catch (f) {
      state = state.copyWith(
        status: SessionStatus.noteReady,
        errorMessage: f.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: SessionStatus.noteReady,
        errorMessage: 'Amendment failed: $e',
      );
    }
  }

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
      await _enableWakeLock();

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
    await _disableWakeLock();

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

  /// Send the clinical session summary via email using SendGrid.
  Future<void> sendSummaryViaSendGrid({required String prescription}) async {
    AppLogger.i('TranscriptionController.sendSummaryViaSendGrid()');
    final note = state.processedNote;
    if (note == null) {
      AppLogger.w('sendSummaryViaSendGrid aborted: No processed note found');
      return;
    }

    final originalNote = state.originalProcessedNote ?? note;
    final amendments = state.amendmentHistory.isEmpty
        ? 'None'
        : state.amendmentHistory.join('\n- ');
    final now = DateTime.now();
    final timestamp =
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    final emailBody = '''
- Original Note -
$originalNote

- Amendments -
$amendments

- Prescription -
$prescription

- Session -
https://storage.googleapis.com/note366-stt-frontend-dev/index.html
''';

    state = state.copyWith(isSendingEmail: true, clearError: true);

    try {
      AppLogger.i('TranscriptionController.sendSummaryViaSendGrid() - Attempting via backend...');
      await _emailService.sendClinicalNoteEmail(
        url: Uri.parse(_config.emailUrl),
        toEmail: 'tharakauop@gmail.com',
        subject: 'Session and $timestamp',
        body: emailBody,
      );
      AppLogger.i('TranscriptionController.sendSummaryViaSendGrid() - SUCCESS');
      state = state.copyWith(isSendingEmail: false);
    } catch (e, stack) {
      AppLogger.e('TranscriptionController.sendSummaryViaSendGrid() - FAILURE: $e', e, stack);
      state = state.copyWith(isSendingEmail: false);
      if (e is Failure) rethrow;
      throw UnexpectedFailure('Could not send email via backend: $e');
    }
  }

  /// Advances the queue to the next patient via QueueService, updates active patient state,
  /// and resets/prepares the recording state for the new session.
  Future<NextPatientResponse?> advanceNextPatient({
    required String doctorId,
    String? practiceCentreId,
    String? visitDate,
  }) async {
    AppLogger.i('TranscriptionController.advanceNextPatient()');
    state = state.copyWith(isAdvancingQueue: true, clearError: true);

    try {
      final response = await _queueService.advanceNextPatient(
        doctorId: doctorId,
        practiceCentreId: practiceCentreId,
        visitDate: visitDate,
      );

      if (response.hasNextPatient && response.activePatient != null) {
        state = state.copyWith(
          isAdvancingQueue: false,
          activePatient: response.activePatient,
        );
      } else {
        state = state.copyWith(
          isAdvancingQueue: false,
          clearActivePatient: true,
        );
      }
      return response;
    } catch (e, stack) {
      AppLogger.e('TranscriptionController.advanceNextPatient() - FAILURE: $e', e, stack);
      state = state.copyWith(
        isAdvancingQueue: false,
        errorMessage: e is Failure ? e.message : 'Failed to advance next patient: $e',
      );
      return null;
    }
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
        originalProcessedNote: event.processedNote, // Initial version
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
    _disableWakeLock();
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

  // ── WidgetsBindingObserver / Lifecycle handlers ──────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.i('AppLifecycleState changed to: $state');
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _handleLifecyclePause();
        break;
      case AppLifecycleState.resumed:
        _handleLifecycleResume();
        break;
      case AppLifecycleState.detached:
        _handleLifecycleDetached();
        break;
      default:
        break;
    }
  }

  Future<void> _handleLifecyclePause() async {
    if (!_isCurrentlyRecording) return;
    if (_pausedAt != null) return;

    _pausedAt = DateTime.now();
    _wasRecordingBeforePause = state.status == SessionStatus.recording;
    _wasCommandBeforePause = state.status == SessionStatus.commandRecording;

    AppLogger.i('Pausing recording due to app lifecycle event. wasRecording=$_wasRecordingBeforePause, wasCommand=$_wasCommandBeforePause');

    try {
      await _activeRepository?.pauseAudioCapture();
    } catch (e) {
      AppLogger.w('Failed to pause audio capture: $e');
    }

    _stopRecordingTicker();
    await _disableWakeLock();
  }

  Future<void> _handleLifecycleResume() async {
    if (_pausedAt == null) return;

    AppLogger.i('Resuming recording due to app lifecycle resume.');

    await _enableWakeLock();

    final pauseDuration = DateTime.now().difference(_pausedAt!);
    _recordingStartedAt = _recordingStartedAt?.add(pauseDuration);
    state = state.copyWith(recordingStartedAt: _recordingStartedAt);
    _pausedAt = null;

    try {
      await _activeRepository?.resumeAudioCapture();
    } catch (e) {
      AppLogger.e('Failed to resume audio capture on app resume', e);
      _failWith('Failed to resume recording: $e');
      return;
    }

    _startRecordingTicker();

    _wasRecordingBeforePause = false;
    _wasCommandBeforePause = false;
  }

  Future<void> _handleLifecycleDetached() async {
    if (_isCurrentlyRecording) {
      AppLogger.i('App detaching: stopping and saving recording.');
      if (state.status == SessionStatus.recording) {
        await stop();
      } else if (state.status == SessionStatus.commandRecording) {
        await stopCommand();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disableWakeLock();
    _processingWatchdog?.cancel();
    _processingWatchdog = null;
    _stopRecordingTicker();
    _disposeActiveRepository();
    super.dispose();
  }
}
