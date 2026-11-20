import 'package:flutter/widgets.dart';

import '../../../core/performance/rebuild_metrics.dart';

/// Counts builds of an expensive surface when profiling is enabled.
/// A no-op passthrough otherwise, so production and tests are unaffected.
class RebuildTracker extends StatelessWidget {
  const RebuildTracker({
    super.key,
    required this.surface,
    required this.child,
  });

  final String surface;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    RebuildMetrics.instance.record(surface);
    return child;
  }
}
