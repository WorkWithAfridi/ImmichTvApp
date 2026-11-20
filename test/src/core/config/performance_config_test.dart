import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/config/performance_config.dart';

void main() {
  test('prefetch window scales with grid density within safe bounds', () {
    expect(PerformanceConfig.prefetchWindowForCrossAxisCount(0), 4);
    expect(PerformanceConfig.prefetchWindowForCrossAxisCount(1), 4);
    expect(PerformanceConfig.prefetchWindowForCrossAxisCount(3), 6);
    expect(PerformanceConfig.prefetchWindowForCrossAxisCount(5), 10);
    expect(PerformanceConfig.prefetchWindowForCrossAxisCount(12), 12);
  });

  test('prefetch queue is slightly larger than the look-ahead window', () {
    expect(PerformanceConfig.maxPrefetchedEntriesForCrossAxisCount(3), 8);
    expect(PerformanceConfig.maxPrefetchedEntriesForCrossAxisCount(12), 14);
  });
}
