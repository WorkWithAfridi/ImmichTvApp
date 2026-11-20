import 'package:flutter/material.dart';

import '../app_colors.dart';

/// A very subtle, static brand glow behind dark surfaces.
///
/// Painted once (no animation) so it adds depth without driving rebuilds or
/// competing with focus rings on large TV panels.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.15,
          colors: [
            AppColors.ambientCenter,
            AppColors.ambientEdge,
          ],
        ),
      ),
      child: child,
    );
  }
}
