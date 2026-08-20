import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../../../design_system/app_spacing.dart';
import '../../../../design_system/widgets/app_buttons.dart';
import '../../../../design_system/widgets/app_card.dart';
import '../../../../design_system/widgets/empty_state.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/services/queue_service.dart';
import '../../data/services/clinical_note_fhir_service.dart';
import '../controllers/transcription_controller.dart';
import '../controllers/transcription_state.dart';
import '../widgets/add_patient_sheet.dart';
import '../widgets/clinical_note_panel.dart';
import '../widgets/config_sheet.dart';
import '../widgets/patient_briefing_card.dart';
import '../widgets/recording_timer.dart';
import '../widgets/session_status_chip.dart';
import '../widgets/status_banner.dart';
import '../widgets/voice_orb.dart';

/// Primary consultation screen — built around the [VoiceOrb].
class TranscriptionScreen extends ConsumerStatefulWidget {
  const TranscriptionScreen({
    super.key,
    this.doctorId,
    this.practiceCentreId,
    this.clinicName,
  });

  final String? doctorId;
  final String? practiceCentreId;
  final String? clinicName;

  @override
  ConsumerState<TranscriptionScreen> createState() =>
      _TranscriptionScreenState();
}

class _TranscriptionScreenState extends ConsumerState<TranscriptionScreen> {
  bool _notePanelOpen = false;
  bool _hasStartedSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initInitialPatient();
    });
  }

  Future<void> _initInitialPatient() async {
    final state = ref.read(transcriptionControllerProvider);
    if (state.activePatient == null) {
      final controller = ref.read(transcriptionControllerProvider.notifier);
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await controller.advanceNextPatient(
        doctorId: _effectiveDoctorId,
        practiceCentreId: _effectivePracticeCentreId,
        visitDate: todayStr,
      );
    }
  }

  String get _effectiveDoctorId {
    if (widget.doctorId != null && widget.doctorId!.isNotEmpty) {
      return widget.doctorId!;
    }
    final authDocId = ref.read(authControllerProvider).doctorId;
    if (authDocId != null && authDocId.isNotEmpty) {
      return authDocId;
    }
    return '';
  }

  String? get _effectivePracticeCentreId => widget.practiceCentreId;

  Future<void> _handleMicPressed() async {
    final controller = ref.read(transcriptionControllerProvider.notifier);
    final state = ref.read(transcriptionControllerProvider);

    if (!state.isRecording) {
      if (_effectiveDoctorId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your doctor account could not be identified. Please sign in again.'),
          ),
        );
        return;
      }

      final alreadyGranted =
          await ref.read(permissionServiceProvider).isMicrophoneGranted();
      if (!alreadyGranted) {
        if (!mounted) return;
        final accepted =
            await PermissionService.confirmMicrophoneDisclosure(context);
        if (!accepted || !mounted) return;
      }
    }

    if (!state.isRecording && state.activePatient == null) {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await controller.advanceNextPatient(
        doctorId: _effectiveDoctorId,
        practiceCentreId: _effectivePracticeCentreId,
        visitDate: todayStr,
      );
    }

    controller.toggleRecording();
  }

  Future<void> _handleFinishConsultation() async {
    final state = ref.read(transcriptionControllerProvider);
    final controller = ref.read(transcriptionControllerProvider.notifier);

    // Persist final (possibly amended) clinical note to FHIR before reset.
    if (state.activePatient != null &&
        (state.processedNote?.trim().isNotEmpty ?? false)) {
      try {
        final now = DateTime.now();
        final todayStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        await controller.saveClinicalNoteToFhir(
          doctorId: _effectiveDoctorId,
          practiceCentreId: _effectivePracticeCentreId ?? '',
          clinicName: widget.clinicName,
          visitDate: todayStr,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is Failure ? e.message : 'Could not save clinical note to FHIR.',
            ),
          ),
        );
        return; // Do not complete consultation if FHIR save failed.
      }
    }

    if (state.activePatient != null) {
      final queueService = ref.read(queueServiceProvider);
      await queueService.updateTicketStatus(state.activePatient!.id, 4); // 4: Completed
    }

    controller.reset();
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _handleNewSession() async {
    await _handleFinishConsultation();
  }

  @override
  Widget build(BuildContext context) {
    // ── React to state changes for navigation/snackbars ──────────────────
    ref.listen<TranscriptionState>(
      transcriptionControllerProvider,
      (prev, next) {
        // Surface errors as a snackbar.
        if (next.status == SessionStatus.error &&
            (prev?.status != SessionStatus.error) &&
            next.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(next.errorMessage!),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Dismiss',
                onPressed: () {
                  ref
                      .read(transcriptionControllerProvider.notifier)
                      .dismissError();
                },
              ),
            ));
        }

        // Auto-open the clinical-note bottom sheet when the note arrives.
        if (next.status == SessionStatus.noteReady &&
            !_notePanelOpen &&
            (next.processedNote?.isNotEmpty ?? false)) {
          _notePanelOpen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await ClinicalNotePanel.show(
              context,
              note: next.processedNote!,
              fullTranscript: next.fullTranscript,
              onNewSession: () async {
                await _handleFinishConsultation();
              },
            );
            _notePanelOpen = false;
          });
        }
      },
    );

    final state = ref.watch(transcriptionControllerProvider);
    final controller = ref.read(transcriptionControllerProvider.notifier);

    // If session hasn't explicitly started yet and recording isn't active, show briefing view
    final bool showBriefingView = !_hasStartedSession &&
        !state.isRecording &&
        !state.isBusy &&
        state.status == SessionStatus.idle;

    return Scaffold(
      body: _AmbientBackground(
        status: state.status,
        amplitude: state.currentAmplitude,
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                status: state.status,
                title: widget.clinicName ?? 'Practice121',
              ),

              if (showBriefingView) ...[
                Expanded(
                  child: state.activePatient != null
                      ? PatientBriefingCard(
                          patient: state.activePatient!,
                          clinicName: widget.clinicName ?? 'Practice121',
                          doctorId: _effectiveDoctorId,
                          practiceCentreId: _effectivePracticeCentreId,
                          isLoading: state.isAdvancingQueue,
                          onStartSession: () {
                            setState(() {
                              _hasStartedSession = true;
                            });
                            _handleMicPressed();
                          },
                        )
                      : Center(
                          child: state.isAdvancingQueue
                              ? const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text('Loading patient details...'),
                                  ],
                                )
                              : EmptyState(
                                  icon: Icons.people_outline_rounded,
                                  title: 'No patients are currently in this session.',
                                  description: 'Add a patient directly to start or conduct this session.',
                                  action: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AppPrimaryButton(
                                        onPressed: () async {
                                          final added = await AddPatientSheet.show(
                                            context,
                                            doctorId: _effectiveDoctorId,
                                            practiceCentreId: _effectivePracticeCentreId ?? '',
                                          );
                                          if (added == true) {
                                            await _initInitialPatient();
                                          }
                                        },
                                        icon: Icons.person_add_rounded,
                                        label: 'Add Patient',
                                      ),
                                      const SizedBox(width: 12),
                                      AppSecondaryButton(
                                        onPressed: () => _initInitialPatient(),
                                        icon: Icons.refresh_rounded,
                                        label: 'Refresh',
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                ),
              ] else ...[
                if (state.activePatient != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 4),
                    child: _ActivePatientBanner(patient: state.activePatient!),
                  ),

                // ── Hero zone: orb + status text ───────────────────────────
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final orbSize =
                          (constraints.maxWidth * 0.78).clamp(220.0, 340.0);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            VoiceOrb(
                              status: state.status,
                              amplitude: state.currentAmplitude,
                              audioLevels: state.audioLevels,
                              onPressed: _handleMicPressed,
                              size: orbSize,
                            ),
                            const SizedBox(height: 28),
                            RecordingTimer(duration: state.recordingElapsed),
                            if (state.recordingElapsed != null)
                              const SizedBox(height: 16),
                            StatusBanner(status: state.status),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ── Bottom action area: contextual cards + config button ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    children: [
                      if (state.status == SessionStatus.noteReady &&
                          (state.processedNote?.isNotEmpty ?? false)) ...[
                        _NoteReadyCard(
                          onOpen: () async {
                            _notePanelOpen = true;
                            await ClinicalNotePanel.show(
                              context,
                              note: state.processedNote!,
                              fullTranscript: state.fullTranscript,
                              onNewSession: () async {
                                await _handleNewSession();
                              },
                            );
                            _notePanelOpen = false;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: state.isRecording || state.isBusy ? 0.35 : 1.0,
                        child: TextButton.icon(
                          onPressed: state.isRecording || state.isBusy
                              ? null
                              : () => ConfigSheet.show(
                                    context,
                                    initial: state.config,
                                    onSave: (cfg) {
                                      controller.updatePrompt(cfg.customPrompt);
                                      controller.updateModel(cfg.modelName);
                                    },
                                  ),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Customize prompt & model'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtle full-screen radial gradient that responds to session state.
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({
    required this.status,
    required this.amplitude,
    required this.child,
  });

  final SessionStatus status;
  final double amplitude;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surface;

    final accent = switch (status) {
      SessionStatus.recording => AppColors.recording,
      SessionStatus.commandRecording => AppColors.recording,
      SessionStatus.processing => AppColors.sparkle,
      SessionStatus.amending => AppColors.sparkle,
      SessionStatus.noteReady => AppColors.success,
      SessionStatus.error => theme.colorScheme.error,
      _ => theme.colorScheme.primary,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.1,
          colors: [
            Color.lerp(
              base,
              accent,
              0.10 + 0.08 * amplitude,
            )!,
            base,
          ],
          stops: const [0.0, 0.85],
        ),
      ),
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.status,
    required this.title,
  });

  final SessionStatus status;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = context.canPop();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => context.pop(),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.medical_services_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SessionStatusChip(status: status),
        ],
      ),
    );
  }
}

class _ActivePatientBanner extends ConsumerWidget {
  const _ActivePatientBanner({required this.patient});

  final QueuePatient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.35),
      ),
      padding: EdgeInsets.zero,
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => _PatientHistorySheet(patient: patient, ref: ref),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '#${patient.queueNumber}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    patient.patientName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (patient.patientMobile.isNotEmpty)
                    Text(
                      patient.patientMobile,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.5),
                ),
              ),
              child: const Text(
                'IN CONSULTATION',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteReadyCard extends StatelessWidget {
  const _NoteReadyCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      color: AppColors.success.withValues(alpha: 0.08),
      border: Border.all(
        color: AppColors.success.withValues(alpha: 0.4),
      ),
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
              const Icon(
                Icons.assignment_turned_in_rounded,
                color: AppColors.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your clinical note is ready',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AppPrimaryButton(
                onPressed: onOpen,
                label: 'Open',
              ),
            ],
          ),
        ),
    );
  }
}

class _PatientHistorySheet extends StatefulWidget {
  const _PatientHistorySheet({required this.patient, required this.ref});
  final QueuePatient patient;
  final WidgetRef ref;

  @override
  State<_PatientHistorySheet> createState() => _PatientHistorySheetState();
}

class _PatientHistorySheetState extends State<_PatientHistorySheet> {
  bool _isLoading = true;
  List<ClinicalNoteSummary>? _notes;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final notes = await widget.ref.read(transcriptionControllerProvider.notifier).loadPriorClinicalNotes();
      if (mounted) {
        setState(() {
          _notes = notes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Previous Sessions', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            widget.patient.patientName,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator()) 
              : (_notes == null || _notes!.isEmpty)
                  ? const Center(child: Text('No previous session history found.'))
                  : ListView.builder(
                      itemCount: _notes!.length,
                      itemBuilder: (ctx, i) {
                        final note = _notes![i];
                        return AppCard(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      note.visitDate ?? 'Unknown Date',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      note.clinicName ?? '',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  note.preview ?? 'No content preview available.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
