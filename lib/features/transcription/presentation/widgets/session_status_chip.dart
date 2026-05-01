import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../controllers/transcription_state.dart';

/// Compact pill that mirrors the React frontend's "STANDBY / LIVE / GENERATING"
/// status indicator in the top-right of the screen.
class SessionStatusChip extends StatelessWidget {
  const SessionStatusChip({super.key, required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, pulsing) = switch (status) {
      SessionStatus.recording => ('LIVE SESSION', AppColors.recording, true),
      SessionStatus.connecting => ('CONNECTING…', AppColors.accent, true),
      SessionStatus.processing => ('GENERATING NOTE', AppColors.sparkle, true),
      SessionStatus.noteReady => ('NOTE READY', AppColors.success, false),
      SessionStatus.error => ('ERROR', theme.colorScheme.error, false),
      SessionStatus.idle => ('STANDBY', theme.colorScheme.outline, false),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: color, pulsing: pulsing),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulsing) {
      return _dot(opacity: 1);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          _dot(opacity: 0.4 + 0.6 * _controller.value),
    );
  }

  Widget _dot({required double opacity}) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
