import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Semantic Colors
  static const Color success = Color(0xFF2E9E5B);
  static const Color warning = Color(0xFFE8A93B);
  static const Color critical = Color(0xFFD64545);
  static const Color info = Color(0xFF3D7EBD);

  // Success Variants
  static const Color successLight = Color(0xFF4AC47A);
  static const Color successDark = Color(0xFF1D7843);
  static const Color successContainer = Color(0xFFD6F0E0);
  
  // Warning Variants
  static const Color warningLight = Color(0xFFFFC661);
  static const Color warningDark = Color(0xFFB57D22);
  static const Color warningContainer = Color(0xFFFDF0D8);

  // Critical Variants
  static const Color criticalLight = Color(0xFFF26868);
  static const Color criticalDark = Color(0xFFA12C2C);
  static const Color criticalContainer = Color(0xFFFCE8E8);

  // Info Variants
  static const Color infoLight = Color(0xFF5A9DE3);
  static const Color infoDark = Color(0xFF275C8F);
  static const Color infoContainer = Color(0xFFE2F0FD);

  static ColorScheme get lightColorScheme {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F6E6A),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF0F6E6A),
      primaryContainer: const Color(0xFFCFEDE9),
      secondary: const Color(0xFF3D5A80),
      surface: const Color(0xFFFAFBFC),
      surfaceContainer: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFF1B2027),
      onSurfaceVariant: const Color(0xFF5B6470),
      outline: const Color(0xFFD8DEE3),
    );
  }

  static ColorScheme get darkColorScheme {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF5FCFC7),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF5FCFC7),
      surface: const Color(0xFF12181B),
      surfaceContainer: const Color(0xFF1A2226),
      onSurface: const Color(0xFFE7EDF0),
      onSurfaceVariant: const Color(0xFF9AA6AD),
      outline: const Color(0xFF2A343A),
    );
  }
}
