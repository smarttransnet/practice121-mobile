import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../controllers/transcription_state.dart';

/// A self-contained voice-recording control built from scratch for Flutter.
///
/// It is the visual heart of the screen and replaces a traditional "button +
/// horizontal bars" combo with a single layered orb whose visuals react in
/// real time to microphone amplitude:
///
///  • **Idle**: a slow breathing sphere — invites a tap, doesn't shout.
///  • **Connecting**: an indeterminate sweeping arc orbits the sphere.
///  • **Recording**: three layers of feedback simultaneously —
///     1. *Ripple rings* expand outward continuously; their stride and
///        opacity scale with the current amplitude (loud voice → wider
///        rings, quiet voice → tight rings).
///     2. *Radial frequency halo*: 36 short bars arranged around the sphere,
///        each bar's length driven by a different sample from the rolling
///        amplitude buffer. Together they read like a polar waveform.
///     3. *Inner core* radius and glow grow with amplitude.
///  • **Processing**: a sparkle shimmer sweeps around the sphere while the
///    AI generates the note.
///  • **Error**: a brief pulse in the error color.
///
/// All of it is rendered in a single CustomPaint so the entire animation
/// runs on one ticker — cheap to repaint at 60 fps even on entry-level
/// hardware.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.status,
    required this.amplitude,
    required this.audioLevels,
    required this.onPressed,
    this.size = 280,
  });

  final SessionStatus status;

  /// Current RMS amplitude on a 0..1 scale (drives the live orb size + glow).
  final double amplitude;

  /// Rolling buffer of the most recent amplitudes, used to populate the
  /// radial frequency halo while recording.
  final List<double> audioLevels;

  final VoidCallback onPressed;
  final double size;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  /// Smoothed amplitude (the raw signal jitters at 10 Hz; smoothing makes
  /// the animation feel buttery without losing reactivity).
  double _smoothedAmp = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Exponential moving average — quick attack, slower release. Floor 0 so
    // tiny noise doesn't make idle visuals jitter.
    final target = widget.amplitude.clamp(0.0, 1.0);
    final alpha = target > _smoothedAmp ? 0.55 : 0.18;
    _smoothedAmp = _smoothedAmp + alpha * (target - _smoothedAmp);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy = widget.status == SessionStatus.connecting ||
        widget.status == SessionStatus.processing;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Semantics(
        button: true,
        label: switch (widget.status) {
          SessionStatus.recording => 'Stop recording',
          SessionStatus.connecting => 'Connecting to Note365',
          SessionStatus.processing => 'Generating clinical note',
          _ => 'Start recording',
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── The painted orb (always visible) ──────────────────────────
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ticker,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _OrbPainter(
                      status: widget.status,
                      amplitude: _smoothedAmp,
                      audioLevels: widget.audioLevels,
                      tick: _ticker.value,
                      primary: theme.colorScheme.primary,
                      secondary: theme.colorScheme.secondary,
                      tertiary: AppColors.sparkle,
                      recording: AppColors.recording,
                      error: theme.colorScheme.error,
                    ),
                  );
                },
              ),
            ),

            // ── Tap target + icon ─────────────────────────────────────────
            // Sized smaller than the orb so the painted glow isn't covered
            // by the gesture detector's clip.
            SizedBox(
              width: widget.size * 0.42,
              height: widget.size * 0.42,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: isBusy ? null : widget.onPressed,
                  splashColor: Colors.white.withValues(alpha: 0.18),
                  highlightColor: Colors.white.withValues(alpha: 0.06),
                  child: Center(
                    child: _CenterIcon(status: widget.status),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterIcon extends StatelessWidget {
  const _CenterIcon({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SessionStatus.connecting:
      case SessionStatus.processing:
        return const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      case SessionStatus.recording:
        return const Icon(Icons.stop_rounded, color: Colors.white, size: 56);
      case SessionStatus.error:
        return const Icon(
          Icons.priority_high_rounded,
          color: Colors.white,
          size: 48,
        );
      case SessionStatus.idle:
      case SessionStatus.noteReady:
        return const Icon(Icons.mic_rounded, color: Colors.white, size: 52);
    }
  }
}

// ─── Painter ────────────────────────────────────────────────────────────────

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.status,
    required this.amplitude,
    required this.audioLevels,
    required this.tick,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.recording,
    required this.error,
  });

  final SessionStatus status;
  final double amplitude; // 0..1 smoothed
  final List<double> audioLevels;
  final double tick; // 0..1 (looping every 6s)
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color recording;
  final Color error;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;

    final isRecording = status == SessionStatus.recording;
    final isProcessing = status == SessionStatus.processing;
    final isError = status == SessionStatus.error;

    // Color palette per state.
    final accent = isRecording
        ? recording
        : isError
            ? error
            : isProcessing
                ? tertiary
                : primary;

    // 1. Outer soft glow disc — always present, modulated by amplitude.
    _paintOuterGlow(canvas, center, maxRadius, accent);

    // 2. Recording-only effects.
    if (isRecording) {
      _paintRipples(canvas, center, maxRadius, accent);
      _paintRadialHalo(canvas, center, maxRadius);
    }

    // 3. Processing shimmer arc.
    if (isProcessing) {
      _paintShimmerArc(canvas, center, maxRadius);
    }

    // 4. Connecting indeterminate orbit.
    if (status == SessionStatus.connecting) {
      _paintConnectingOrbit(canvas, center, maxRadius, primary);
    }

    // 5. Inner sphere — the visible "button" backdrop.
    _paintInnerSphere(canvas, center, maxRadius, accent);
  }

  void _paintOuterGlow(
    Canvas canvas,
    Offset center,
    double maxRadius,
    Color accent,
  ) {
    final breath = 0.5 + 0.5 * math.sin(tick * 2 * math.pi);
    final pulse = 0.45 + 0.55 * amplitude;
    final radius = maxRadius * (0.78 + 0.05 * breath + 0.08 * amplitude);

    final shader = RadialGradient(
      colors: [
        accent.withValues(alpha: 0.22 * pulse),
        accent.withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    final paint = Paint()..shader = shader;
    canvas.drawCircle(center, radius, paint);
  }

  void _paintRipples(
    Canvas canvas,
    Offset center,
    double maxRadius,
    Color accent,
  ) {
    // Three ripple rings, evenly phase-offset, each looping over a short
    // sub-interval of `tick`. Faster + wider when amplitude rises.
    const ringCount = 3;
    final speed = 1 + amplitude * 1.2;
    for (var i = 0; i < ringCount; i++) {
      final phase = (tick * speed + i / ringCount) % 1.0;
      final base = maxRadius * 0.5;
      final spread = maxRadius * (0.45 + 0.35 * amplitude);
      final radius = base + phase * spread;
      final opacity = (1 - phase) * (0.35 + 0.45 * amplitude);
      if (opacity <= 0) continue;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + 1.5 * amplitude
        ..color = accent.withValues(alpha: opacity.clamp(0.0, 0.8));
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintRadialHalo(Canvas canvas, Offset center, double maxRadius) {
    if (audioLevels.isEmpty) return;

    const barCount = 36;
    final innerRadius = maxRadius * 0.46;
    final maxBarLen = maxRadius * 0.34;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.4;

    for (var i = 0; i < barCount; i++) {
      // Map each bar to a sample from the rolling buffer. Wrap so we get a
      // smooth circle even when buffer length != bar count.
      final sampleIdx = (i * audioLevels.length / barCount).floor() %
          audioLevels.length;
      final raw = audioLevels[sampleIdx].clamp(0.0, 1.0);
      // Perceptual curve: even a quiet voice ought to budge the ring.
      final curved = math.pow(raw, 0.55).toDouble();

      final angle = -math.pi / 2 + (i / barCount) * 2 * math.pi;
      final inner = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      final length = 6 + curved * maxBarLen;
      final outer = Offset(
        center.dx + (innerRadius + length) * math.cos(angle),
        center.dy + (innerRadius + length) * math.sin(angle),
      );

      final t = i / barCount;
      paint.shader = LinearGradient(
        colors: [
          primary,
          secondary,
        ],
      ).createShader(
        Rect.fromCenter(center: center, width: maxRadius * 2, height: maxRadius * 2),
      );
      paint.color = Color.lerp(primary, secondary, t)!
          .withValues(alpha: 0.55 + 0.45 * curved);
      canvas.drawLine(inner, outer, paint);
    }
  }

  void _paintShimmerArc(Canvas canvas, Offset center, double maxRadius) {
    final radius = maxRadius * 0.62;
    final start = tick * 2 * math.pi;
    const sweep = math.pi * 0.6;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: [
          tertiary.withValues(alpha: 0.0),
          tertiary,
          secondary,
          tertiary.withValues(alpha: 0.0),
        ],
      ).createShader(rect);

    canvas.drawArc(rect, start, sweep, false, paint);
  }

  void _paintConnectingOrbit(
    Canvas canvas,
    Offset center,
    double maxRadius,
    Color color,
  ) {
    final radius = maxRadius * 0.58;
    final start = tick * 2 * math.pi;
    const sweep = math.pi * 0.35;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = color.withValues(alpha: 0.85);
    canvas.drawArc(rect, start, sweep, false, paint);
  }

  void _paintInnerSphere(
    Canvas canvas,
    Offset center,
    double maxRadius,
    Color accent,
  ) {
    // Diameter swells gently with amplitude.
    final radius = maxRadius * (0.32 + 0.06 * amplitude);

    // Drop shadow for depth.
    final shadow = Paint()
      ..color = accent.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(center, radius, shadow);

    // Main body — radial gradient for a glassy 3-D feel.
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        radius: 0.95,
        colors: [
          Color.lerp(accent, Colors.white, 0.35)!,
          accent,
          Color.lerp(accent, Colors.black, 0.25)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, body);

    // Specular highlight (top-left).
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(
      center.translate(-radius * 0.3, -radius * 0.4),
      radius * 0.32,
      highlight,
    );

    // Subtle outer ring.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.28);
    canvas.drawCircle(center, radius, ring);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) {
    // Always repaint while the ticker animates; cheap because we draw shapes.
    return old.tick != tick ||
        old.amplitude != amplitude ||
        old.status != status ||
        !identical(old.audioLevels, audioLevels);
  }
}
