import 'dart:math';

import 'package:flutter/material.dart';

/// Slowly moves the wallpaper clock so a bright element does not sit in one
/// place for hours on an OLED television.
class WallpaperClockPolicy {
  const WallpaperClockPolicy._();

  static const maxHorizontalDrift = 48.0;
  static const maxVerticalDrift = 24.0;

  static Offset drift(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    final horizontal = minutes / (24 * 60) * 2 * pi;
    final vertical = minutes / (24 * 60) * 4 * pi;
    return Offset(
      sin(horizontal) * maxHorizontalDrift,
      cos(vertical) * maxVerticalDrift,
    );
  }
}
