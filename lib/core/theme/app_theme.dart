import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class _Palette {
  const _Palette({
    required this.bg,
    required this.sidebar,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.teal,
    required this.danger,
    required this.success,
    required this.codeBg,
  });

  final Color bg, sidebar, surface, surfaceHigh, border, text, muted, accent, teal, danger, success, codeBg;
}

const _darkPalette = _Palette(
  bg: Color(0xFF0B0E16),
  sidebar: Color(0xFF10131F),
  surface: Color(0xFF151928),
  surfaceHigh: Color(0xFF1E2335),
  border: Color(0xFF272E45),
  text: Color(0xFFE8E9F3),
  muted: Color(0xFF8B90A8),
  accent: Color(0xFF7C6DF2),
  teal: Color(0xFF2DD9A8),
  danger: Color(0xFFFF6B81),
  success: Color(0xFF3DDC97),
  codeBg: Color(0xFF0A0C14),
);

const _lightPalette = _Palette(
  bg: Color(0xFFF6F6FB),
  sidebar: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  surfaceHigh: Color(0xFFEEEEF7),
  border: Color(0xFFDBDCEA),
  text: Color(0xFF15172A),
  muted: Color(0xFF5C6079),
  accent: Color(0xFF5B4BD6),
  teal: Color(0xFF0E9F79),
  danger: Color(0xFFE0405E),
  success: Color(0xFF1E9A6C),
  codeBg: Color(0xFFF0F0F7),
);

/// Every existing `AppColors.xxx` call site in the app reads through these
/// getters, so calling [AppColors.apply] and rebuilding the tree (done once
/// per frame in the app root) is enough to re-skin the whole UI — no need to
/// thread BuildContext into every custom widget individually.
class AppColors {
  const AppColors._();

  static _Palette _current = _darkPalette;

  static void apply(Brightness brightness) {
    _current = brightness == Brightness.dark ? _darkPalette : _lightPalette;
  }

  static Color get bg => _current.bg;
  static Color get sidebar => _current.sidebar;
  static Color get surface => _current.surface;
  static Color get surfaceHigh => _current.surfaceHigh;
  static Color get border => _current.border;
  static Color get text => _current.text;
  static Color get muted => _current.muted;
  static Color get accent => _current.accent;
  static Color get teal => _current.teal;
  static Color get danger => _current.danger;
  static Color get success => _current.success;
  static Color get codeBg => _current.codeBg;
}

class AppTheme {
  const AppTheme._();

  static TextStyle mono({double size = 13, Color? color, FontWeight? weight}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color, fontWeight: weight, height: 1.5);

  static ThemeData build(Brightness brightness) {
    final p = brightness == Brightness.dark ? _darkPalette : _lightPalette;
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme =
        GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: p.text, displayColor: p.text);
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.sidebar,
      textTheme: textTheme,
      colorScheme: brightness == Brightness.dark
          ? ColorScheme.dark(
              primary: p.accent,
              onPrimary: Colors.white,
              secondary: p.teal,
              surface: p.surface,
              onSurface: p.text,
              error: p.danger,
              outline: p.border,
            )
          : ColorScheme.light(
              primary: p.accent,
              onPrimary: Colors.white,
              secondary: p.teal,
              surface: p.surface,
              onSurface: p.text,
              error: p.danger,
              outline: p.border,
            ),
      dividerColor: p.border,
      appBarTheme: AppBarTheme(
        backgroundColor: p.sidebar,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: p.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          foregroundColor: p.text,
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

/// Shared text-field look (kept as a helper so it is immune to
/// InputDecorationTheme API changes between Flutter versions).
InputDecoration fieldDecoration(String label, {String? hint, IconData? icon, Widget? suffix}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.surface,
    enabledBorder: b(AppColors.border),
    focusedBorder: b(AppColors.accent, 1.5),
    errorBorder: b(AppColors.danger),
    focusedErrorBorder: b(AppColors.danger, 1.5),
    labelStyle: TextStyle(color: AppColors.muted),
  );
}
