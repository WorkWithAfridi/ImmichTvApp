/// Lightweight rebuild counters for the surfaces most likely to churn while
/// scrolling a large TV library.
///
/// Opt in at build time with:
///   flutter run --dart-define=immichtv.profile=true
class RebuildMetrics {
  RebuildMetrics._();

  static final instance = RebuildMetrics._();

  static const isEnabled = bool.fromEnvironment(
    'immichtv.profile',
    defaultValue: false,
  );

  final Map<String, int> _counts = <String, int>{};

  void record(String surface) {
    if (!isEnabled) {
      return;
    }
    _counts[surface] = (_counts[surface] ?? 0) + 1;
  }

  Map<String, int> snapshot() => Map<String, int>.unmodifiable(_counts);

  void reset() => _counts.clear();
}
