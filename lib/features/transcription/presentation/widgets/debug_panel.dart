import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/constants/audio_constants.dart';
import '../controllers/transcription_controller.dart';
import '../controllers/transcription_state.dart';
import 'live_transcript_view.dart';

// ── Test-recording state ─────────────────────────────────────────────────────
enum _TestRecState { idle, recording, done, error }

/// Side panel shown via the Scaffold's end drawer.
///
/// Contains:
///   • Live diagnostics (status, rate, audio level, endpoint)
///   • Rolling live transcript (interim + finals)
///   • **"Record 3 s test WAV"** — saves a short raw recording to the device
///     filesystem so you can pull it with `adb pull` and verify the mic is
///     delivering clean audio before it hits the WebSocket pipeline.
class DebugPanel extends ConsumerStatefulWidget {
  const DebugPanel({super.key});

  @override
  ConsumerState<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends ConsumerState<DebugPanel> {
  _TestRecState _testState = _TestRecState.idle;
  String? _testFilePath;
  int? _testFileBytes;
  String? _testError;
  AudioRecorder? _testRecorder;

  @override
  void dispose() {
    _testRecorder?.dispose();
    super.dispose();
  }

  Future<void> _runTestRecording() async {
    setState(() {
      _testState = _TestRecState.recording;
      _testFilePath = null;
      _testFileBytes = null;
      _testError = null;
    });

    final recorder = AudioRecorder();
    _testRecorder = recorder;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/test_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

      // The `record` package wraps PCM in a WAV container automatically when
      // the path ends in `.wav`, giving us a playable file.
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: AudioConstants.sampleRate,
          numChannels: AudioConstants.channels,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
        ),
        path: path,
      );

      // Record for 3 seconds then stop.
      await Future<void>.delayed(const Duration(seconds: 3));

      final resultPath = await recorder.stop();
      _testRecorder = null;

      if (resultPath == null) {
        throw Exception('recorder.stop() returned null path');
      }

      final fileSize = File(resultPath).lengthSync();
      setState(() {
        _testState = _TestRecState.done;
        _testFilePath = resultPath;
        _testFileBytes = fileSize;
      });
    } catch (e) {
      try {
        await recorder.stop();
      } catch (_) {}
      _testRecorder = null;
      setState(() {
        _testState = _TestRecState.error;
        _testError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transcriptionControllerProvider);
    final config = ref.watch(appConfigProvider);
    final theme = Theme.of(context);

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.92,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.bug_report_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Debug — Live transcript',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ── Diagnostics card ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _DiagnosticsCard(state: state, config: config),
            ),

            // ── Mic test card ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _MicTestCard(
                testState: _testState,
                filePath: _testFilePath,
                fileBytes: _testFileBytes,
                error: _testError,
                onTap: _testState == _TestRecState.recording
                    ? null
                    : _runTestRecording,
              ),
            ),

            const Divider(height: 1),

            // ── Transcript list ──────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
                child: LiveTranscriptView(
                  finals: state.finals,
                  interim: state.interim,
                ),
              ),
            ),

            // ── Footer ───────────────────────────────────────────────────────
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.finals.isEmpty
                          ? null
                          : () => _copyTranscript(context, state),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy transcript'),
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

  Future<void> _copyTranscript(
    BuildContext context,
    TranscriptionState state,
  ) async {
    final buf = StringBuffer();
    for (final f in state.finals) {
      if (f.speakerLabel.isNotEmpty) {
        buf.write('[${f.speakerLabel}] ');
      }
      buf.writeln(f.text);
    }
    if (state.interim.isNotEmpty) {
      buf.writeln('(interim) ${state.interim}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Live transcript copied to clipboard')),
    );
  }
}

// ── Mic test card ────────────────────────────────────────────────────────────

class _MicTestCard extends StatelessWidget {
  const _MicTestCard({
    required this.testState,
    required this.filePath,
    required this.fileBytes,
    required this.error,
    required this.onTap,
  });

  final _TestRecState testState;
  final String? filePath;
  final int? fileBytes;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mic_none_rounded,
                size: 15,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Text(
                'Mic quality test',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (testState == _TestRecState.recording)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FilledButton.tonal(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(34),
              textStyle: theme.textTheme.labelMedium,
            ),
            child: Text(
              testState == _TestRecState.recording
                  ? 'Recording 3 s…'
                  : 'Record 3 s test WAV',
            ),
          ),
          if (testState == _TestRecState.done && filePath != null) ...[
            const SizedBox(height: 6),
            _InfoLine(
              theme: theme,
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.success,
              text: 'Saved  •  ${_kb(fileBytes!)} KB',
            ),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: () =>
                  Clipboard.setData(ClipboardData(text: filePath!)),
              child: _InfoLine(
                theme: theme,
                icon: Icons.file_copy_outlined,
                color: theme.colorScheme.primary,
                text: filePath!,
                underline: true,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pull with:  adb pull "$filePath" .',
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.outline,
              ),
            ),
            Text(
              'If playback sounds clean → mic is fine, issue is in streaming.\n'
              'If garbled / silent → emulator audio pipeline is the problem.\n'
              'Use a real device for reliable STT.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                height: 1.5,
              ),
            ),
          ],
          if (testState == _TestRecState.error && error != null) ...[
            const SizedBox(height: 6),
            _InfoLine(
              theme: theme,
              icon: Icons.error_outline_rounded,
              color: theme.colorScheme.error,
              text: error!,
            ),
          ],
        ],
      ),
    );
  }

  static String _kb(int bytes) => (bytes / 1024).toStringAsFixed(1);
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.theme,
    required this.icon,
    required this.color,
    required this.text,
    this.underline = false,
  });

  final ThemeData theme;
  final IconData icon;
  final Color color;
  final String text;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontFamily: 'monospace',
              decoration:
                  underline ? TextDecoration.underline : TextDecoration.none,
              overflow: TextOverflow.ellipsis,
            ),
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}

// ── Diagnostics card ─────────────────────────────────────────────────────────

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({required this.state, required this.config});

  final TranscriptionState state;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ampPct = (state.currentAmplitude * 100).round();
    final dbfs = _toDbfs(state.currentAmplitude);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(theme, 'Status', _statusLabel(state.status),
              color: _statusColor(theme, state.status)),
          _row(theme, 'Finals received', '${state.finals.length}'),
          _row(
            theme,
            'Interim',
            state.interim.isEmpty ? '(none)' : '"${state.interim}"',
            mono: true,
          ),
          _row(
            theme,
            'Audio level',
            '$ampPct%  /  ${dbfs.toStringAsFixed(1)} dBFS',
            mono: true,
          ),
          if (state.recordingElapsed != null)
            _row(
              theme,
              'Elapsed',
              _formatElapsed(state.recordingElapsed!),
              mono: true,
            ),
          if (state.audioBytesPerSecond != null)
            _row(
              theme,
              'Audio rate',
              _rateLabel(state.audioBytesPerSecond!),
              mono: true,
              color: _rateColor(theme, state.audioBytesPerSecond!),
            ),
          const SizedBox(height: 4),
          _row(
            theme,
            'Sample rate',
            '${AudioConstants.sampleRate} Hz, PCM16 mono',
            mono: true,
          ),
          _row(theme, 'Endpoint', config.transcriptionWsUrl, mono: true),
        ],
      ),
    );
  }

  static String _statusLabel(SessionStatus s) => switch (s) {
        SessionStatus.idle => 'idle',
        SessionStatus.connecting => 'connecting',
        SessionStatus.recording => 'recording',
        SessionStatus.processing => 'processing',
        SessionStatus.noteReady => 'note ready',
        SessionStatus.error => 'error',
      };

  static Color _statusColor(ThemeData theme, SessionStatus s) => switch (s) {
        SessionStatus.recording => AppColors.recording,
        SessionStatus.processing => AppColors.sparkle,
        SessionStatus.noteReady => AppColors.success,
        SessionStatus.error => theme.colorScheme.error,
        _ => theme.colorScheme.outline,
      };

  // Output = 16 000 Hz × 2 bytes = 32 000 B/s
  static const _expectedBps = 32000.0;

  static String _rateLabel(double bps) {
    final ratio = bps / _expectedBps;
    return '${bps.toStringAsFixed(0)} B/s  '
        '(${(ratio * 100).toStringAsFixed(0)}%)';
  }

  static Color _rateColor(ThemeData theme, double bps) {
    final ratio = bps / _expectedBps;
    if (ratio >= 0.90 && ratio <= 1.10) return AppColors.success;
    if (ratio >= 0.50 && ratio < 0.90) return theme.colorScheme.tertiary;
    return theme.colorScheme.error;
  }

  static double _toDbfs(double rms) {
    if (rms <= 0) return -120;
    return 20 * (math.log(rms) / math.ln10);
  }

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    Color? color,
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color ?? theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
