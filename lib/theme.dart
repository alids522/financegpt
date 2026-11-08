import 'package:flutter/material.dart';

const accent = Color(0xFF1978F8);
ThemeData financeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final text = dark ? const Color(0xFFF2F6FD) : const Color(0xFF101827);
  final secondary = dark ? const Color(0xFFB7C6DB) : const Color(0xFF53657D);
  final surface = dark ? const Color(0xFF1A2839) : const Color(0xFFF7FAFF);
  final border = dark
      ? const Color(0xFF536378).withValues(alpha: .50)
      : Colors.white.withValues(alpha: .88);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: dark ? const Color(0xFF72C9FF) : accent,
        onPrimary: dark ? const Color(0xFF061729) : Colors.white,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: secondary,
        outline: border,
        surfaceContainerHighest: dark
            ? const Color(0xFF29394D)
            : const Color(0xFFE6EEFC),
        error: dark ? const Color(0xFFFF969F) : const Color(0xFFBC3446),
      );
  final textTheme = Typography.material2021(
    platform: TargetPlatform.android,
    colorScheme: scheme,
  ).black.apply(fontFamily: 'Inter', bodyColor: text, displayColor: text);
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(15),
    borderSide: BorderSide(
      color: dark ? const Color(0xFF52647C) : const Color(0xFFCAD8EC),
    ),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Inter',
    textTheme: textTheme.copyWith(
      bodySmall: textTheme.bodySmall?.copyWith(color: secondary, height: 1.45),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.45),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: surface.withValues(alpha: dark ? .66 : .72),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: dark
          ? Colors.white.withValues(alpha: .09)
          : const Color(0xFF8BA5C8).withValues(alpha: .18),
      thickness: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    iconTheme: IconThemeData(color: secondary, size: 22),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF172537) : const Color(0xFFF4F8FF),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? Colors.white.withValues(alpha: .04)
          : Colors.white.withValues(alpha: .60),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(
          color: dark ? const Color(0xFF647891) : const Color(0xFFCAD9EF),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 7,
      focusElevation: 8,
      hoverElevation: 9,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface.withValues(alpha: .5),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(
        scheme.primary.withValues(alpha: dark ? .12 : .06),
      ),
      headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: text),
      horizontalMargin: 16,
      columnSpacing: 24,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: dark
          ? const Color(0xFF46576D)
          : const Color(0xFFDCE5F3),
    ),
  );
}
