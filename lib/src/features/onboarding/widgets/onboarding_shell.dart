import 'package:flutter/material.dart';

import '../../../shared/presentation/app_colors.dart';
import '../../../shared/presentation/app_breakpoints.dart';

class OnboardingShell extends StatelessWidget {
  const OnboardingShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ColoredBox(
        color: AppColors.background,
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final viewportWidth = viewportConstraints.maxWidth;
            final isTvLayout = viewportWidth >= AppBreakpoints.tv;
            final horizontalPadding = isTvLayout
                ? 40.0
                : viewportWidth < AppBreakpoints.tablet
                ? 24.0
                : 32.0;
            final panelWidthFactor = isTvLayout
                ? 0.42
                : viewportWidth < AppBreakpoints.tablet
                ? 0.94
                : 0.62;
            final panelMaxWidth = (viewportWidth * panelWidthFactor).clamp(
              360.0,
              760.0,
            );
            final panelPadding = (viewportWidth * (isTvLayout ? 0.018 : 0.03))
                .clamp(24.0, 36.0);
            final safeTop = isTvLayout ? 0.0 : mediaQuery.padding.top;
            final safeBottom = isTvLayout ? 0.0 : mediaQuery.padding.bottom;

            return Padding(
              padding: EdgeInsets.only(
                left: horizontalPadding + mediaQuery.padding.left,
                right: horizontalPadding + mediaQuery.padding.right,
                top: (isTvLayout ? 20.0 : 24.0) + safeTop,
                bottom: (isTvLayout ? 20.0 : 24.0) + safeBottom,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: panelMaxWidth),
                        child: Padding(
                          padding: EdgeInsets.all(panelPadding),
                          child: SingleChildScrollView(child: child),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
