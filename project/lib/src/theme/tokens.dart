import 'package:flutter/material.dart';

/// Layout constants taken from the web client's `stoatWebTheme.ts`.
class Radius_ {
  static const xs = 4.0,
      sm = 8.0,
      md = 12.0,
      lg = 16.0,
      li = 20.0,
      xl = 28.0,
      xli = 32.0,
      xxl = 48.0;
}

class Gap {
  static const xxs = 1.0,
      xs = 2.0,
      s = 6.0,
      sm = 4.0,
      md = 8.0,
      l = 12.0,
      lg = 15.0,
      x = 28.0,
      xl = 32.0,
      xxl = 64.0;
}

class Layout {
  static const channelSidebarWidth = 248.0;
  static const serverRailWidth = 56.0;
  static const messageBoxHeightFactor = 0.32;
}

BorderRadius br(double r) => BorderRadius.circular(r);

extension SchemeX on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}
