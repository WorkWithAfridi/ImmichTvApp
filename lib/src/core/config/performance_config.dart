import 'dart:math';

/// Central defaults for scrolling and thumbnail prefetch behavior.
///
/// Keeping these in one place makes it possible to tune TV-class hardware
/// without hunting through widget trees for magic numbers.
class PerformanceConfig {
  const PerformanceConfig._();

  static const int minPrefetchWindow = 4;
  static const int maxPrefetchWindow = 12;
  static const int defaultPrefetchWindow = 10;
  static const double listCacheExtent = 480;
  static const double gridCacheExtent = 240;

  /// Roughly two rows/columns of look-ahead, bounded so a dense TV grid does
  /// not evict visible thumbnails while prefetching.
  static int prefetchWindowForCrossAxisCount(int crossAxisCount) {
    if (crossAxisCount <= 0) {
      return minPrefetchWindow;
    }
    return min(
      max(crossAxisCount * 2, minPrefetchWindow),
      maxPrefetchWindow,
    );
  }

  static int maxPrefetchedEntriesForCrossAxisCount(int crossAxisCount) {
    return prefetchWindowForCrossAxisCount(crossAxisCount) + 2;
  }
}
