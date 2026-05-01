import 'package:flutter/material.dart';

import '../controllers/transcription_state.dart';

/// State-driven primary/secondary status text below the orb.
///
/// Smoothly cross-fades when the status changes — the visual heartbeat of
/// the screen, telling the user exactly what the app is doing without
/// requiring them to interpret icons.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (title, subtitle) = switch (status) {
      SessionStatus.idle => (
        'Ready when you are',
        'Tap the orb to start a clinical session',
      ),
      SessionStatus.connecting => (
        'Connecting…',
        'Linking up with Note365 securely',
      ),
      SessionStatus.recording => (
        'Listening',
        'Speak naturally — the AI is taking notes',
      ),
      SessionStatus.processing => (
        'Crafting your note',
        'The AI is summarizing your session into SOAP format',
      ),
      SessionStatus.noteReady => (
        'Your note is ready',
        'Open it below to review, copy, or share',
      ),
      SessionStatus.error => (
        'Something went wrong',
        'Tap the orb to try again',
      ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(status),
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
