import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/review_prompt_service.dart';
import '../../shared/presentation/app_colors.dart';
import '../../shared/presentation/app_durations.dart';
import '../../shared/presentation/app_focus_decoration.dart';
import '../../shared/presentation/app_radii.dart';
import '../../shared/presentation/app_spacing.dart';
import '../../shared/presentation/widgets/tv_focusable.dart';

const _playStoreReviewUrl =
    'https://play.google.com/store/apps/details?id=com.workwithafridi.immichtv';

Future<void> maybeShowReviewPromptDialog(
  BuildContext context, {
  required ReviewPromptService reviewPromptService,
}) async {
  final status = await reviewPromptService.getStatus();
  if (!context.mounted || !status.shouldPrompt) {
    return;
  }

  final result = await Navigator.of(context).push<_ReviewPromptResult>(
    PageRouteBuilder<_ReviewPromptResult>(
      opaque: true,
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          const _ReviewPromptScreen(),
      transitionsBuilder: (routeContext, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );

  if (!context.mounted) {
    return;
  }

  if (result == _ReviewPromptResult.done) {
    await reviewPromptService.completePrompt();
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (routeContext, animation, secondaryAnimation) =>
            const _ReviewThankYouScreen(),
        transitionsBuilder:
            (routeContext, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
      ),
    );
    return;
  }

  await reviewPromptService.deferPrompt();
}

enum _ReviewPromptResult { done, notNow }

class _ReviewPromptScreen extends StatefulWidget {
  const _ReviewPromptScreen();

  @override
  State<_ReviewPromptScreen> createState() => _ReviewPromptScreenState();
}

class _ReviewPromptScreenState extends State<_ReviewPromptScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF091117),
        body: SafeArea(
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    Navigator.of(context).pop(_ReviewPromptResult.notNow);
                    return null;
                  },
                ),
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 560;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? AppSpacing.md : AppSpacing.lg,
                          vertical: compact ? AppSpacing.md : AppSpacing.lg,
                        ),
                        child: FocusTraversalGroup(
                          policy: WidgetOrderTraversalPolicy(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ReviewPromptHero(theme: theme, compact: compact),
                              SizedBox(
                                height: compact ? AppSpacing.md : AppSpacing.lg,
                              ),
                              Text(
                                'A quick Google Play review helps us reach more people, improve the app faster, and keep Immich TV growing for the living room. Scan this QR code with your phone to open the Immich TV Google Play page and leave a review.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  height: 1.4,
                                ),
                              ),
                              SizedBox(
                                height: compact ? AppSpacing.md : AppSpacing.lg,
                              ),
                              _PhoneQrPanel(compact: compact),
                              SizedBox(
                                height: compact ? AppSpacing.md : AppSpacing.lg,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _ReviewPromptButton(
                                      label: 'Not now',
                                      autofocus: true,
                                      compact: compact,
                                      onPressed: () => Navigator.of(
                                        context,
                                      ).pop(_ReviewPromptResult.notNow),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: _ReviewPromptButton(
                                      label: 'Done',
                                      compact: compact,
                                      onPressed: () => Navigator.of(
                                        context,
                                      ).pop(_ReviewPromptResult.done),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneQrPanel extends StatelessWidget {
  const _PhoneQrPanel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('phone-qr-panel'),
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useVerticalLayout = constraints.maxWidth < 560;
          final qrCode = Container(
            padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: QrImageView(
              data: _playStoreReviewUrl,
              version: QrVersions.auto,
              size: compact ? 168 : 192,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                color: AppColors.darkBackground,
                eyeShape: QrEyeShape.square,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                color: AppColors.darkBackground,
                dataModuleShape: QrDataModuleShape.square,
              ),
            ),
          );

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan on your phone',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Point your phone camera at the QR code and it will open the Immich TV Google Play page.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                  height: 1.4,
                ),
              ),
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              Text(
                'Prefer to share feedback directly? Email afridi.khondakar@gmail.com',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          );

          if (useVerticalLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: qrCode),
                SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                content,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              qrCode,
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewPromptHero extends StatelessWidget {
  const _ReviewPromptHero({required this.theme, required this.compact});

  final ThemeData theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.rate_review_rounded,
          color: AppColors.immichBlue,
          size: 36,
        ),
        SizedBox(width: compact ? AppSpacing.md : AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enjoying Immich TV?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewThankYouScreen extends StatelessWidget {
  const _ReviewThankYouScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF091117),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: FocusTraversalGroup(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.favorite_rounded,
                        color: AppColors.success,
                        size: 56,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Thank you',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Your support really helps us reach more people and keep improving Immich TV.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.84),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: 260,
                        child: _ReviewPromptButton(
                          label: 'Close',
                          autofocus: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewPromptButton extends StatelessWidget {
  const _ReviewPromptButton({
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focusState) {
        final isFocused = focusState.isFocused;
        final backgroundColor = Colors.white.withValues(alpha: 0.04);
        final activeBackgroundColor = Colors.white.withValues(alpha: 0.1);

        return AnimatedContainer(
          duration: AppDurations.normal,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.md : AppSpacing.lg,
            vertical: compact ? AppSpacing.sm : AppSpacing.md,
          ),
          decoration: AppFocusDecoration.surface(
            isFocused: isFocused,
            isActive: focusState.isActive,
            backgroundColor: backgroundColor,
            activeBackgroundColor: activeBackgroundColor,
            borderRadius: BorderRadius.circular(AppRadii.md),
            glow: true,
          ),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      },
    );
  }
}
