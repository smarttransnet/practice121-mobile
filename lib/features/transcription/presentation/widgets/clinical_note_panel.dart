import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/logging/app_logger.dart';

/// Modal sheet that displays the Gemini-generated clinical note.
///
/// Provides:
///   • Copy to clipboard
///   • Share via the OS share sheet (saves to a .txt file first)
///   • Optionally a button to start a new session
class ClinicalNotePanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: fullTranscript != null && fullTranscript!.isNotEmpty ? 2 : 1,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 12, 12, 4),
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
                    tooltip: 'Copy',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: note),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    tooltip: 'Share',
                    onPressed: () => _shareNote(context),
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                ],
              ),
            ),
            if (fullTranscript != null && fullTranscript!.isNotEmpty)
              TabBar(
                tabs: const [
                  Tab(text: 'Note'),
                  Tab(text: 'Full transcript'),
                ],
                labelColor: theme.colorScheme.primary,
                indicatorColor: theme.colorScheme.primary,
              ),
            const Divider(height: 1),
            Expanded(
              child: fullTranscript != null && fullTranscript!.isNotEmpty
                  ? TabBarView(
                      children: [
                        _NoteBody(text: note),
                        _NoteBody(text: fullTranscript!),
                      ],
                    )
                  : _NoteBody(text: note),
            ),
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
    );
  }

  Future<void> _shareNote(BuildContext context) async {
    try {
      final dir = await getTemporaryDirectory();
      final filename =
          'Note365_Clinical_Note_${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt';
      final file = File('${dir.path}/$filename');

      final body = StringBuffer()
        ..writeln('Note365 — Clinical Note')
        ..writeln('Generated: ${DateTime.now().toLocal()}')
        ..writeln('-' * 42)
        ..writeln()
        ..writeln(note);

      if (fullTranscript != null && fullTranscript!.isNotEmpty) {
        body
          ..writeln()
          ..writeln('-' * 42)
          ..writeln('Full transcript')
          ..writeln('-' * 42)
          ..writeln()
          ..writeln(fullTranscript);
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

class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SelectableText(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
      ),
    );
  }
}
