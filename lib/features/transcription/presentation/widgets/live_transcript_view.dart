import 'package:flutter/material.dart';

import '../../data/models/transcription_event.dart';

/// Scrolling list of finalized utterances + the current uncommitted interim.
///
/// Used inside the debug side panel — kept out of the main hero UI so the
/// doctor sees a calm recording experience, but available for QA / engineers
/// to verify that interim and final transcripts are flowing correctly.
class LiveTranscriptView extends StatefulWidget {
  const LiveTranscriptView({
    super.key,
    required this.finals,
    required this.interim,
  });

  final List<FinalUtterance> finals;
  final String interim;

  @override
  State<LiveTranscriptView> createState() => _LiveTranscriptViewState();
}

class _LiveTranscriptViewState extends State<LiveTranscriptView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant LiveTranscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.finals.length != widget.finals.length ||
        oldWidget.interim != widget.interim) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.finals.isEmpty && widget.interim.isEmpty) {
      return _Empty(theme: theme);
    }

    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final entry in widget.finals)
            _UtteranceTile(entry: entry, theme: theme),
          if (widget.interim.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Icon(
                        Icons.fiber_manual_record,
                        size: 10,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.interim,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UtteranceTile extends StatelessWidget {
  const _UtteranceTile({required this.entry, required this.theme});

  final FinalUtterance entry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(entry.timestamp).format(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (entry.speakerLabel.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.speakerLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                time,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const Spacer(),
              if (entry.confidence > 0)
                Text(
                  'conf ${entry.confidence.toStringAsFixed(2)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            entry.text,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.subtitles_off_rounded,
              size: 32,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No transcripts yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start a recording — interim and final transcripts from Google STT will stream in here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
