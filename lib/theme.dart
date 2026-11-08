import 'package:flutter/material.dart';

const accent = Color(0xFF456D9A);
ThemeData financeTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final text = dark ? const Color(0xFFEDF0F2) : const Color(0xFF20252B);
  final border = dark ? const Color(0xFF30363D) : const Color(0xFFDFE3E8);
  final surface = dark ? const Color(0xFF191D22) : Colors.white;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b)
      .copyWith(
        primary: dark ? const Color(0xFF7B9BC0) : accent,
        surface: surface,
        outline: border,
        onSurface: text,
        onSurfaceVariant: dark
            ? const Color(0xFF9BA4AE)
            : const Color(0xFF68727D),
        surfaceContainerHighest: dark
            ? const Color(0xFF22272D)
            : const Color(0xFFEFF2F5),
        error: dark ? const Color(0xFFD88989) : const Color(0xFFB64D52),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF101317)
        : const Color(0xFFF7F8FA),
    fontFamily: 'Inter',
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textTheme: Typography.material2021(
      platform: TargetPlatform.android,
      colorScheme: scheme,
    ).black.apply(fontFamily: 'Inter', bodyColor: text, displayColor: text),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(
        dark ? const Color(0xFF22272D) : const Color(0xFFEFF2F5),
      ),
      headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: text),
      horizontalMargin: 16,
      columnSpacing: 24,
    ),
  );
}
