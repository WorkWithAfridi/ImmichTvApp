import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/performance/rebuild_metrics.dart';

void main() {
  test('counts are recorded per surface and can be reset', () {
    final metrics = RebuildMetrics.instance;
    metrics.reset();

    metrics.record('home.content');
    metrics.record('home.content');
    metrics.record('home.sidebar');

    if (RebuildMetrics.isEnabled) {
      expect(metrics.snapshot()['home.content'], 2);
      expect(metrics.snapshot()['home.sidebar'], 1);
      expect(metrics.snapshot(), isNot(same(metrics.snapshot())));
    } else {
      expect(metrics.snapshot(), isEmpty);
    }

    metrics.reset();
    expect(metrics.snapshot(), isEmpty);
  });
}
