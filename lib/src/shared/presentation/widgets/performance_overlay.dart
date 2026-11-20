import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

import '../../../core/performance/rebuild_metrics.dart';
import '../app_colors.dart';
import '../app_radii.dart';
import '../app_spacing.dart';

/// Debug-only HUD showing image cache pressure and rebuild counts.
/// Only mounted when `immichtv.profile` is set via `--dart-define`.
class ImmichPerformanceOverlay extends StatefulWidget {
  const ImmichPerformanceOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<ImmichPerformanceOverlay> createState() =>
      _ImmichPerformanceOverlayState();
}

class _ImmichPerformanceOverlayState extends State<ImmichPerformanceOverlay> {
  Timer? _timer;
  Map<String, int> _counts = const <String, int>{};
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) {
      return;
    }
    setState(() => _counts = RebuildMetrics.instance.snapshot());
  }

  @override
  Widget build(BuildContext context) {
    final cache = PaintingBinding.instance.imageCache;
    final entries = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final summary = entries.take(_expanded ? 12 : 4).map(
      (entry) => '${entry.key}: ${entry.value}',
    );

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: AppSpacing.md,
          bottom: AppSpacing.md,
          child: ExcludeFocus(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: const Color(0xCC071017),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.focus),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'PERF  (tap to expand)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.focus,
                        ),
                      ),
                      Text(
                        'images ${cache.currentSize}/${cache.maximumSize}  '
                        '${(cache.currentSizeBytes / (1 << 20)).toStringAsFixed(1)}/'
                        '${(cache.maximumSizeBytes / (1 << 20)).toStringAsFixed(1)} MB',
                      ),
                      ...summary.map((line) => Text(line)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
