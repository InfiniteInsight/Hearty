import 'package:flutter/material.dart';

import 'theme/aurora_colors.dart';

class AppTheme {
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB71C1C),
        ),
      );

  /// Dark Aurora theme (Hearty UI Design Guide). Applied per-screen as the app
  /// is migrated to the design system; screens wrap their content in
  /// `Theme(data: AppTheme.aurora, ...)` over the [Aurora.background] gradient.
  static ThemeData get aurora {
    const scheme = ColorScheme.dark(
      primary: Aurora.accentGreen,
      onPrimary: Color(0xFF052E20),
      secondary: Aurora.accentViolet,
      surface: Aurora.bgBottom,
      onSurface: Aurora.textPrimary,
      error: Aurora.accentRed,
      onError: Color(0xFF3A0D0D),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      fontFamily: 'Plus Jakarta Sans',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Aurora.textPrimary,
        centerTitle: false,
      ),
      textTheme: const TextTheme().apply(
        bodyColor: Aurora.textPrimary,
        displayColor: Aurora.textPrimary,
      ),
      iconTheme: const IconThemeData(color: Aurora.textSecondary),
      listTileTheme: const ListTileThemeData(
        textColor: Aurora.textPrimary,
        iconColor: Aurora.textSecondary,
        subtitleTextStyle: TextStyle(color: Aurora.textMuted, fontSize: 12),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Aurora.accentGreen,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Aurora.bgTop,
        contentTextStyle: TextStyle(color: Aurora.textPrimary),
      ),
    );
  }
}
