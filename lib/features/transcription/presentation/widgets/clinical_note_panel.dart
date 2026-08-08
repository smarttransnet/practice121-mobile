import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/models/prescription_item.dart';
import '../controllers/transcription_controller.dart';
import 'prescription_grid_widget.dart';

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
    this.keyboardOpen = false,
  });

  final String note;
  final String? fullTranscript;
  final VoidCallback onNewSession;
  final bool keyboardOpen;

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
      builder: (sheetContext) {
        final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(context).height;
              // Sit entirely above the IME. Use full remaining height while
              // typing so the editor is not crushed to 0px.
              final sheetHeight =
                  keyboardInset > 0 ? maxHeight : maxHeight * 0.85;
              return SizedBox(
                height: sheetHeight,
                child: ClinicalNotePanel(
                  note: note,
                  fullTranscript: fullTranscript,
                  onNewSession: onNewSession,
                  keyboardOpen: keyboardInset > 0,
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(transcriptionControllerProvider);

    // Use the latest note from state if available (it might have been amended),
    // otherwise fall back to the one passed during initial .show().
    final currentNote = state.processedNote ?? note;

    return DefaultTabController(
      length: fullTranscript != null && fullTranscript!.isNotEmpty ? 2 : 1,
      child: SafeArea(
        top: false,
        child: Column(
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
                        PrescriptionGridWidget(
                          initialRawPrescription: _extractPrescription(currentNote),
                          onPrescriptionChanged: (items, rawJson, sentenceText) {
                            // Update local or amended note state with new formatted prescription
                          },
                        ),
                      ],
                    )
                  : _NoteBody(text: currentNote),
            ),

            // ── Amendment Section (Talk to Edit / Type to Edit) ─────────────
            const Divider(height: 1),
            const _AmendmentSection(),

            // SMS / Close / Finish stay pinned only when the keyboard is closed.
            // While typing they crush the Expanded editor to 0px and paint under
            // the IME (see clinical_note_panel_keyboard_test.dart).
            if (!keyboardOpen) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: OutlinedButton.icon(
                  onPressed: state.isSendingSms
                      ? null
                      : () async {
                          final targetPhone =
                              (state.activePatient?.patientMobile.isNotEmpty ??
                                      false)
                                  ? state.activePatient!.patientMobile
                                  : '0775706080';
                          try {
                            await ref
                                .read(transcriptionControllerProvider.notifier)
                                .sendPrescriptionViaSms(
                                  mobileNumber: targetPhone,
                                  prescription: _getAsciiPrescriptionForSms(
                                    currentNote,
                                  ),
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Prescription SMS sent to $targetPhone',
                                  ),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to send SMS: $e'),
                                  backgroundColor: theme.colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                  icon: state.isSendingSms
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sms_rounded, color: AppColors.accent),
                  label: const Text('Send SMS Prescription'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Finish Consultation'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
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

  String _getAsciiPrescriptionForSms(String note) {
    final rawText = _extractPrescription(note);
    final items = PrescriptionItem.fromRaw(rawText);
    if (items.isNotEmpty) {
      return items.map((i) => i.toSmsAsciiString()).where((s) => s.isNotEmpty).join('\n');
    }
    return PrescriptionItem.sanitizeToAscii(rawText);
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
              scrollPadding: const EdgeInsets.fromLTRB(20, 40, 20, 80),
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
