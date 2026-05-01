import 'package:flutter/material.dart';

/// Centralized color palette so the brand can be retuned in one place.
/// Inspired by the React frontend's deep-indigo / cyan accent system.
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────────────────────
  static const Color brand = Color(0xFF4F46E5);          // indigo-600
  static const Color brandSoft = Color(0xFF6366F1);      // indigo-500
  static const Color accent = Color(0xFF06B6D4);         // cyan-500
  static const Color accentSoft = Color(0xFF22D3EE);     // cyan-400
  static const Color sparkle = Color(0xFFA855F7);        // purple-500

  // ── Status ─────────────────────────────────────────────────────────────
  static const Color recording = Color(0xFFEF4444);      // red-500
  static const Color recordingHalo = Color(0x33EF4444);  // red-500 @ 20%
  static const Color success = Color(0xFF22C55E);        // green-500

  // ── Surfaces ───────────────────────────────────────────────────────────
  static const Color darkSurface = Color(0xFF0B1020);
  static const Color darkSurfaceElevated = Color(0xFF111933);
  static const Color darkOnSurfaceMuted = Color(0xFFA0A8C7);

  static const Color lightSurface = Color(0xFFF6F7FB);
  static const Color lightSurfaceElevated = Colors.white;
}
