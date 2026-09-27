import 'package:flutter/material.dart';

/// Windows 11 design tokens — built on Flutter core only, no fluent_ui.
abstract final class NtColors {
  static const accentLight = Color(0xFF0067C0);
  static const accentDark = Color(0xFF4CC2FF);
  static const surfaceLight = Color(0xFFF9F9F9);
  static const surfaceDark = Color(0xFF202020);
  static const cardLight = Color(0xFFFDFDFD);
  static const cardDark = Color(0xFF2C2C2C);
  static const borderLight = Color(0xFFE5E5E5);
  static const borderDark = Color(0xFF404040);
  static const textLight = Color(0xFF1B1B1B);
  static const textDark = Color(0xFFECECEC);
  static const secondaryLight = Color(0xFF606060);
  static const secondaryDark = Color(0xFFA6A6A6);
}

abstract final class NtTheme {
  static const _fontFamily = 'Segoe UI Variable Text';
  static const _fontFallback = ['Segoe UI'];

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final accent = dark ? NtColors.accentDark : NtColors.accentLight;
    final surface = dark ? NtColors.surfaceDark : NtColors.surfaceLight;
    final card = dark ? NtColors.cardDark : NtColors.cardLight;
    final border = dark ? NtColors.borderDark : NtColors.borderLight;
    final text = dark ? NtColors.textDark : NtColors.textLight;
    final secondary = dark ? NtColors.secondaryDark : NtColors.secondaryLight;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: dark ? Colors.black : Colors.white,
        secondary: accent,
        onSecondary: dark ? Colors.black : Colors.white,
        error: const Color(0xFFC42B1C),
        onError: Colors.white,
        surface: surface,
        onSurface: text,
        surfaceContainerHighest: card,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: text),
        titleMedium: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: text),
        bodyMedium: TextStyle(fontSize: 14, color: text),
        bodySmall: TextStyle(fontSize: 12, color: secondary),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      // Thin track + round thumb — the Win11 slider look.
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: accent,
        inactiveTrackColor: border,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 8, elevation: 0, pressedElevation: 0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: dark ? Colors.black : Colors.white,
          disabledBackgroundColor: border,
          disabledForegroundColor: secondary,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
