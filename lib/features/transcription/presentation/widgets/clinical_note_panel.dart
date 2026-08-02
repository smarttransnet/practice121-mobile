import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/logging/app_logger.dart';
import '../controllers/transcription_controller.dart';

/// Modal sheet that displays the Gemini-generated clinical note.
///
/// Provides:
///   • Copy to clipboard
///   • Share via the OS share sheet (saves to a .txt file first)
///   • **Talk to Edit** & **Type to Edit** (Gemini-powered amendments)
///   • Optionally a button to start a new session
class ClinicalNotePanel extends ConsumerWidget {
  const ClinicalNotePanel({
    super.key,
    required this.note,
    required this.fullTranscript,
    required this.onNewSession,
  });

  final String note;
  final String? fullTranscript;
  final VoidCallback onNewSession;

  static Future<void> show(
    BuildContext context, {
    required String note,
    required String? fullTranscript,
    required VoidCallback onNewSession,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => ClinicalNotePanel(
          note: note,
          fullTranscript: fullTranscript,
          onNewSession: onNewSession,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(transcriptionControllerProvider);

    // Use the latest note from state if available (it might have been amended),
    // otherwise fall back to the one passed during initial .show().
    final currentNote = state.processedNote ?? note;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return DefaultTabController(
      length: fullTranscript != null && fullTranscript!.isNotEmpty ? 2 : 1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Clinical Note',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Email summary',
                    onPressed: state.isSendingEmail
                        ? null
                        : () async {
                            try {
                              await ref
                                  .read(transcriptionControllerProvider.notifier)
                                  .sendSummaryViaSendGrid(
                                    prescription:
                                        _extractPrescription(currentNote),
                                  );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Email sent to tharakauop@gmail.com'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to send email: $e'),
                                    backgroundColor: theme.colorScheme.error,
                                  ),
                                );
                              }
                            }
                          },
                    icon: state.isSendingEmail
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          )
                        : const Icon(Icons.email_rounded),
                  ),
                  IconButton(
                    tooltip: 'Share',
                    onPressed: () => _shareNote(context, currentNote),
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                ],
              ),
            ),
            if (fullTranscript != null && fullTranscript!.isNotEmpty)
              TabBar(
                tabs: const [
                  Tab(text: 'Note'),
                  Tab(text: 'Prescription'),
                ],
                labelColor: theme.colorScheme.primary,
                indicatorColor: theme.colorScheme.primary,
              ),
            const Divider(height: 1),
            Expanded(
              child: fullTranscript != null && fullTranscript!.isNotEmpty
                  ? TabBarView(
                      children: [
                        _NoteBody(text: currentNote),
                        _NoteBody(text: _extractPrescription(currentNote)),
                      ],
                    )
                  : _NoteBody(text: currentNote),
            ),

            // ── Amendment Section (Talk to Edit / Type to Edit) ─────────────
            const Divider(height: 1),
            const _AmendmentSection(),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onNewSession();
                      },
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text('New session'),
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

  String _extractPrescription(String note) {
    final markers = [
      '**Doctor Prescription**',
      'DOCTOR PRESCRIPTION',
      'Doctor Prescription:',
      'Doctor Prescription',
    ];

    for (final marker in markers) {
      final index = note.indexOf(marker);
      if (index != -1) {
        var start = index + marker.length;
        final rest = note.substring(start);
        final match = RegExp(r'^[\s─\n=]*').firstMatch(rest);
        if (match != null) {
          start += match.end;
        }
        return note.substring(start).trim();
      }
    }
    return 'No prescription found in note.';
  }

  Future<void> _shareNote(BuildContext context, String currentNote) async {
    try {
      final dir = await getTemporaryDirectory();
      final filename =
          'Practice121_Clinical_Note_${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt';
      final file = File('${dir.path}/$filename');

      final body = StringBuffer()
        ..writeln('Practice121 — Clinical Note')
        ..writeln('Generated: ${DateTime.now().toLocal()}')
        ..writeln('-' * 42)
        ..writeln()
        ..writeln(currentNote);

      final prescription = _extractPrescription(currentNote);
      if (prescription.isNotEmpty &&
          !prescription.startsWith('No prescription')) {
        body
          ..writeln()
          ..writeln('-' * 42)
          ..writeln('Prescription')
          ..writeln('-' * 42)
          ..writeln()
          ..writeln(prescription);
      }

      await file.writeAsString(body.toString());
      if (!context.mounted) return;
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      AppLogger.w('Share failed: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share note: $e')),
      );
    }
  }
}

class _AmendmentSection extends ConsumerStatefulWidget {
  const _AmendmentSection();

  @override
  ConsumerState<_AmendmentSection> createState() => _AmendmentSectionState();
}

class _AmendmentSectionState extends ConsumerState<_AmendmentSection> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(transcriptionControllerProvider);
    final controller = ref.read(transcriptionControllerProvider.notifier);

    if (state.isAmending) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Gemini is updating your note...',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    if (state.isCommandRecording) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.mic, color: AppColors.recording),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.amendmentCommand.isEmpty
                    ? 'Listening for command...'
                    : state.amendmentCommand,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: state.amendmentCommand.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
            IconButton.filled(
              onPressed: controller.stopCommand,
              icon: const Icon(Icons.stop_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.recording,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: 'Talk or type to edit...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: IconButton(
                  icon: const Icon(Icons.mic_rounded),
                  onPressed: controller.startCommand,
                  color: theme.colorScheme.primary,
                ),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  controller.amendNote(val.trim());
                  _ctrl.clear();
                }
              },
            ),
          ),
          if (_ctrl.text.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () {
                controller.amendNote(_ctrl.text.trim());
                _ctrl.clear();
              },
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SelectableText.rich(
        _parseStyledText(text, theme),
        textAlign: TextAlign.left,
      ),
    );
  }

  TextSpan _parseStyledText(String text, ThemeData theme) {
    final List<InlineSpan> spans = [];
    final RegExp regExp = RegExp(r'\*\*(.*?)\*\*');
    int lastMatchEnd = 0;

    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.5,
      color: theme.textTheme.bodyLarge?.color,
    );

    for (final Match match in regExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: baseStyle?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ));
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    if (spans.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    return TextSpan(children: spans);
  }
}
