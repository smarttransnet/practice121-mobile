import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../controllers/transcription_controller.dart';
import '../controllers/transcription_state.dart';
import '../widgets/clinical_note_panel.dart';
import '../widgets/config_sheet.dart';
import '../widgets/debug_panel.dart';
import '../widgets/recording_timer.dart';
import '../widgets/session_status_chip.dart';
import '../widgets/status_banner.dart';
import '../widgets/voice_orb.dart';

/// Primary screen — built around the [VoiceOrb] as the single dominant
/// control. No live-transcript card by design (the doctor wants a calm,
/// focused recording experience; the verbatim transcript is available in the
/// "Full transcript" tab of the clinical-note panel).
class TranscriptionScreen extends ConsumerStatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  ConsumerState<TranscriptionScreen> createState() =>
      _TranscriptionScreenState();
}

class _TranscriptionScreenState extends ConsumerState<TranscriptionScreen> {
  bool _notePanelOpen = false;

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
              onNewSession: () {
                ref.read(transcriptionControllerProvider.notifier).reset();
                ref.read(transcriptionControllerProvider.notifier).start();
              },
            );
            _notePanelOpen = false;
          });
        }
      },
    );

    final state = ref.watch(transcriptionControllerProvider);
    final controller = ref.read(transcriptionControllerProvider.notifier);

    return Scaffold(
      // End drawer surfaces the live transcript + diagnostics for debug only.
      // Doctors don't see this unless they explicitly tap the bug icon in the
      // header, keeping the primary recording UX calm and focused.
      endDrawer: const DebugPanel(),
      // Ambient gradient that morphs with the session status — gives the
      // whole screen a state-aware mood without adding any extra UI chrome.
      body: _AmbientBackground(
        status: state.status,
        amplitude: state.currentAmplitude,
        child: SafeArea(
          child: Column(
            children: [
              _Header(status: state.status),

              // ── Hero zone: orb + status text ───────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Make the orb scale with screen size so small phones
                    // (5") still see a comfortable tap target and large
                    // phones / tablets aren't dwarfed by negative space.
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
                            onPressed: controller.toggleRecording,
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
                            onNewSession: () {
                              controller.reset();
                              controller.start();
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
      SessionStatus.processing => AppColors.sparkle,
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
  const _Header({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
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
          const SizedBox(width: 10),
          Text('Note365', style: theme.textTheme.titleLarge),
          const Spacer(),
          SessionStatusChip(status: status),
          const SizedBox(width: 4),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Live transcript (debug)',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              icon: Icon(
                Icons.bug_report_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
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
    return Card(
      color: AppColors.success.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppColors.success.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
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
              FilledButton(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
