import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/viewer/wallpaper_clock_policy.dart';

void main() {
  test('drift stays within safe bounds across the day', () {
    for (var hour = 0; hour < 24; hour++) {
      final drift = WallpaperClockPolicy.drift(DateTime(2026, 1, 1, hour));
      expect(drift.dx.abs(), lessThanOrEqualTo(WallpaperClockPolicy.maxHorizontalDrift));
      expect(drift.dy.abs(), lessThanOrEqualTo(WallpaperClockPolicy.maxVerticalDrift));
    }
  });

  test('drift changes throughout the day so a static clock does not burn in', () {
    final morning = WallpaperClockPolicy.drift(DateTime(2026, 1, 1, 8));
    final evening = WallpaperClockPolicy.drift(DateTime(2026, 1, 1, 20));
    expect(morning, isNot(evening));
  });
}
