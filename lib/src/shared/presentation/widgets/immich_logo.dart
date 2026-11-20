import 'dart:math';

import 'package:flutter/material.dart';

/// Animated Immich-inspired flower mark, drawn with a painter so it stays
/// sharp at any TV density and does not depend on a static cover image.
class ImmichLogo extends StatefulWidget {
  const ImmichLogo({
    super.key,
    required this.size,
    this.duration = const Duration(milliseconds: 1400),
  });

  final double size;
  final Duration duration;

  @override
  State<ImmichLogo> createState() => _ImmichLogoState();
}

class _ImmichLogoState extends State<ImmichLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant ImmichLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Immich TV',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final value = _controller.value;
            final petalScales = List<double>.generate(8, (index) {
              final start = index * 0.055;
              return const Interval(
                0,
                0.45,
                curve: Curves.easeOutBack,
              ).transform(((value - start) / (1 - start)).clamp(0, 1));
            });
            final rotation = -0.35 + 0.35 * Curves.easeOutCubic.transform(value);
            final centerScale = const Interval(
              0.42,
              0.78,
              curve: Curves.easeOutBack,
            ).transform(value);

            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: ImmichFlowerPainter(
                  petalScales: petalScales,
                  rotation: rotation,
                  centerScale: centerScale,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ImmichFlowerPainter extends CustomPainter {
  const ImmichFlowerPainter({
    required this.petalScales,
    required this.rotation,
    required this.centerScale,
  });

  // Clockwise from the top, sampled to match the Immich flower mark.
  static const _petalColors = <Color>[
    Color(0xFFF8715B), // coral
    Color(0xFFFFA63C), // orange
    Color(0xFFFFD34F), // yellow
    Color(0xFFA7D94B), // lime
    Color(0xFF22C6D4), // cyan
    Color(0xFF3F86E8), // blue
    Color(0xFF8E63D6), // violet
    Color(0xFFEA6A9E), // pink
  ];

  final List<double> petalScales;
  final double rotation;
  final double centerScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final petalRadius = size.width * 0.29;
    const orbitRatio = 0.215;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    for (var index = 0; index < _petalColors.length; index++) {
      final scale = petalScales[index];
      if (scale <= 0) {
        continue;
      }

      final angle = index * 2 * pi / _petalColors.length - pi / 2;
      final orbit = size.width * orbitRatio;
      final offset = Offset(cos(angle) * orbit, sin(angle) * orbit);
      final paint = Paint()
        ..color = _petalColors[index].withValues(alpha: 0.74)
        ..blendMode = BlendMode.srcOver
        ..style = PaintingStyle.fill;

      canvas.drawCircle(offset, petalRadius * scale, paint);
    }

    canvas.restore();

    if (centerScale > 0) {
      final centerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        center,
        size.width * 0.105 * centerScale,
        centerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ImmichFlowerPainter oldDelegate) {
    return rotation != oldDelegate.rotation ||
        centerScale != oldDelegate.centerScale ||
        !_sameScales(petalScales, oldDelegate.petalScales);
  }

  static bool _sameScales(List<double> a, List<double> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
