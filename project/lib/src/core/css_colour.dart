import 'package:flutter/painting.dart';

/// Parses `#rrggbb` (role gradients use their first colour).
Color? parseCssColour(String? css) {
  if (css == null) return null;
  final m = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(css);
  if (m == null) return null;
  return Color(int.parse('FF${m.group(1)}', radix: 16));
}
