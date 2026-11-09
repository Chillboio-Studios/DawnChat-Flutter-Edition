import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/settings_store.dart';

Color parseHex(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

DynamicSchemeVariant _variant(String v) => switch (v) {
  'monochrome' => DynamicSchemeVariant.monochrome,
  'neutral' => DynamicSchemeVariant.neutral,
  'vibrant' => DynamicSchemeVariant.vibrant,
  'expressive' => DynamicSchemeVariant.expressive,
  'fidelity' => DynamicSchemeVariant.fidelity,
  'content' => DynamicSchemeVariant.content,
  'rainbow' => DynamicSchemeVariant.rainbow,
  'fruit_salad' => DynamicSchemeVariant.fruitSalad,
  _ => DynamicSchemeVariant.tonalSpot,
};

TextStyle _fontStyle(String family, [TextStyle? base]) {
  try {
    return GoogleFonts.getFont(family, textStyle: base);
  } catch (_) {
    return GoogleFonts.openSans(textStyle: base);
  }
}

TextStyle monoStyle(SettingsStore s, [TextStyle? base]) =>
    _fontStyle(s.monospaceFont, base);

/// Builds the Material You theme equivalent to the web client's generated CSS variables.
ThemeData buildTheme(SettingsStore s, Brightness platformBrightness) {
  final dark =
      s.mode == 'dark' ||
      (s.mode == 'system' && platformBrightness == Brightness.dark);
  final scheme = ColorScheme.fromSeed(
    seedColor: parseHex(s.m3Accent),
    brightness: dark ? Brightness.dark : Brightness.light,
    contrastLevel: s.m3Contrast,
    dynamicSchemeVariant: _variant(s.m3Variant),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: scheme.brightness,
  );
  final family = _fontStyle(s.interfaceFont).fontFamily;
  final text = base.textTheme.apply(
    fontFamily: family,
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surfaceContainer,
    canvasColor: scheme.surfaceContainer,
    textTheme: text,
    primaryTextTheme: text,
    dividerColor: scheme.outlineVariant,
    splashFactory: InkSparkle.splashFactory,
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHigh,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
}

class StatusColors {
  static const online = Color(0xFF3ABF7E);
  static const idle = Color(0xFFF39F00);
  static const focus = Color(0xFF4799F0);
  static const busy = Color(0xFFF84848);
  static const invisible = Color(0xFFA5A5A5);

  static Color of(String? presence) => switch (presence) {
    'Online' => online,
    'Idle' => idle,
    'Focus' => focus,
    'Busy' => busy,
    _ => invisible,
  };
}

/// Matches the web `Breakpoint` queries (phone / tablet / desktop).
enum ScreenClass { phone, tablet, desktop }

ScreenClass screenClassOf(Size size) => size.width <= 600
    ? ScreenClass.phone
    : (size.width <= 840 || size.height <= 600)
    ? ScreenClass.tablet
    : ScreenClass.desktop;
