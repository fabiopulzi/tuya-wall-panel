import 'package:material_ui/material_ui.dart';

import '../models/models.dart';

/// Design tokens for the wall panel.
///
/// Dark by default: the panel lives on a wall 24h and must not light up a
/// dark hallway. Color is reserved for things that are *on*, so a glance at
/// the screen tells you what is running in the house.
abstract final class AppColors {
  static const background = Color(0xFF0D1015);
  static const surface = Color(0xFF161A21);
  static const surfaceRaised = Color(0xFF1D222B);
  static const surfaceHigh = Color(0xFF262C37);
  static const border = Color(0xFF2A303B);

  static const textPrimary = Color(0xFFF3F4F6);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textTertiary = Color(0xFF6B7280);

  /// Warm light glow — lights that are on.
  static const light = Color(0xFFFFB648);

  /// Sockets and generic loads.
  static const plug = Color(0xFF34D3A6);

  /// Pool pump and water related loads.
  static const water = Color(0xFF4CC2FF);

  static const danger = Color(0xFFFF6B6B);

  static Color forKind(DeviceKind kind) => switch (kind) {
    DeviceKind.light => light,
    DeviceKind.plug => plug,
    DeviceKind.pump => water,
    DeviceKind.other => plug,
  };
}

abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppRadius {
  static const card = 28.0;
  static const tile = 22.0;
  static const pill = 999.0;
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    surface: AppColors.surface,
    primary: AppColors.light,
    onPrimary: Color(0xFF231600),
    secondary: AppColors.plug,
    error: AppColors.danger,
    onSurface: AppColors.textPrimary,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          // Clock
          displayLarge: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w300,
            letterSpacing: -2.5,
            height: 1,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          // Room sheet title
          headlineMedium: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
            color: AppColors.textPrimary,
          ),
          // Card title
          titleLarge: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: AppColors.textPrimary,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          labelMedium: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: AppColors.textTertiary,
          ),
        ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 15),
    ),
  );
}
