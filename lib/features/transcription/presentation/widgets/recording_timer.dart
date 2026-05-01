import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// A compact mm:ss elapsed-time chip displayed under the orb while recording.
///
/// Renders nothing (`SizedBox.shrink`) when [duration] is null, so the layout
/// doesn't jump when the session is idle.
class RecordingTimer extends StatelessWidget {
  const RecordingTimer({
    super.key,
    required this.duration,
    this.showLiveDot = true,
  });

  final Duration? duration;
  final bool showLiveDot;

  @override
  Widget build(BuildContext context) {
    final d = duration;
    if (d == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.recording.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.recording.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLiveDot) ...[
            const _BlinkingDot(),
            const SizedBox(width: 8),
          ],
          Text(
            _format(d),
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.recording,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.recording.withValues(
            alpha: 0.4 + 0.6 * _c.value,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.recording.withValues(alpha: 0.6 * _c.value),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
