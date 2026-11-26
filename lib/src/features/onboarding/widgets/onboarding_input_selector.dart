import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/presentation/app_colors.dart';
import '../../../shared/presentation/app_durations.dart';
import '../../../shared/presentation/app_focus_decoration.dart';
import '../../../shared/presentation/app_radii.dart';
import '../../../shared/presentation/app_scale.dart';
import '../../../shared/presentation/widgets/tv_focusable.dart';
import 'onboarding_input_method.dart';

class OnboardingInputSelector extends StatelessWidget {
  const OnboardingInputSelector({
    super.key,
    required this.theme,
    required this.selectedMethod,
    required this.tvFocusNode,
    required this.nativeFocusNode,
    required this.phoneFocusNode,
    required this.onMethodSelected,
    required this.onPhoneSetup,
  });

  final ThemeData theme;
  final OnboardingInputMethod selectedMethod;
  final FocusNode tvFocusNode;
  final FocusNode nativeFocusNode;
  final FocusNode phoneFocusNode;
  final ValueChanged<OnboardingInputMethod> onMethodSelected;
  final VoidCallback onPhoneSetup;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            _MoveSelectorFocusIntent.left(),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            _MoveSelectorFocusIntent.right(),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            _MoveSelectorFocusIntent.down(),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            _MoveSelectorFocusIntent.up(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveSelectorFocusIntent: CallbackAction<_MoveSelectorFocusIntent>(
            onInvoke: (intent) {
              switch (intent.direction) {
                case TraversalDirection.left:
                  if (phoneFocusNode.hasFocus) {
                    nativeFocusNode.requestFocus();
                  } else if (nativeFocusNode.hasFocus) {
                    tvFocusNode.requestFocus();
                  }
                case TraversalDirection.right:
                  if (tvFocusNode.hasFocus) {
                    nativeFocusNode.requestFocus();
                  } else if (nativeFocusNode.hasFocus) {
                    phoneFocusNode.requestFocus();
                  }
                case TraversalDirection.down:
                  if (tvFocusNode.hasFocus) {
                    nativeFocusNode.requestFocus();
                  } else if (nativeFocusNode.hasFocus) {
                    phoneFocusNode.requestFocus();
                  }
                case TraversalDirection.up:
                  if (phoneFocusNode.hasFocus) {
                    nativeFocusNode.requestFocus();
                  } else if (nativeFocusNode.hasFocus) {
                    tvFocusNode.requestFocus();
                  }
              }
              return null;
            },
          ),
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isStacked = constraints.maxWidth < 880;
                final cardWidth = isStacked
                    ? constraints.maxWidth
                    : ((constraints.maxWidth -
                                  scale.space(12, min: 10, max: 16)) /
                              2)
                          .clamp(180.0, 280.0);

                return Wrap(
                  spacing: scale.space(12, min: 10, max: 16),
                  runSpacing: scale.space(12, min: 10, max: 16),
                  alignment: WrapAlignment.center,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _InputMethodCard(
                        focusNode: tvFocusNode,
                        title: 'Screen keyboard',
                        description:
                            'Use the keyboard that appears on screen. Best when you only have the remote and want to finish setup without another device.',
                        icon: Icons.keyboard_rounded,
                        selected:
                            selectedMethod == OnboardingInputMethod.tvKeyboard,
                        onPressed: () =>
                            onMethodSelected(OnboardingInputMethod.tvKeyboard),
                        onMoveRight: isStacked
                            ? null
                            : () => nativeFocusNode.requestFocus(),
                        onMoveUp: null,
                        onMoveDown: () => nativeFocusNode.requestFocus(),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _InputMethodCard(
                        focusNode: nativeFocusNode,
                        title: 'Device keyboard',
                        description:
                            'Use a physical keyboard or the system keyboard on this device. Best when you are running the app on a desktop, laptop, or touch device.',
                        icon: Icons.keyboard_alt_rounded,
                        selected:
                            selectedMethod ==
                            OnboardingInputMethod.nativeKeyboard,
                        onPressed: () => onMethodSelected(
                          OnboardingInputMethod.nativeKeyboard,
                        ),
                        onMoveLeft: isStacked
                            ? null
                            : () => tvFocusNode.requestFocus(),
                        onMoveRight: isStacked
                            ? null
                            : () => phoneFocusNode.requestFocus(),
                        onMoveUp: () => tvFocusNode.requestFocus(),
                        onMoveDown: () => phoneFocusNode.requestFocus(),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _InputMethodCard(
                        focusNode: phoneFocusNode,
                        title: 'Use phone',
                        description:
                            'Enter your server URL and sign-in details on your phone instead of typing them on the TV.',
                        icon: Icons.qr_code_2_rounded,
                        selected: false,
                        onPressed: onPhoneSetup,
                        onMoveLeft: isStacked
                            ? null
                            : () => nativeFocusNode.requestFocus(),
                        onMoveRight: null,
                        onMoveUp: () => nativeFocusNode.requestFocus(),
                        onMoveDown: null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InputMethodCard extends StatelessWidget {
  const _InputMethodCard({
    required this.focusNode,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
  });

  final FocusNode focusNode;
  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);

    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            onMoveLeft?.call();
            return onMoveLeft == null
                ? KeyEventResult.ignored
                : KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            onMoveRight?.call();
            return onMoveRight == null
                ? KeyEventResult.ignored
                : KeyEventResult.handled;
          case LogicalKeyboardKey.arrowUp:
            onMoveUp?.call();
            return onMoveUp == null
                ? KeyEventResult.ignored
                : KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            onMoveDown?.call();
            return onMoveDown == null
                ? KeyEventResult.ignored
                : KeyEventResult.handled;
          default:
            return KeyEventResult.ignored;
        }
      },
      child: TvFocusable(
        focusNode: focusNode,
        onPressed: onPressed,
        builder: (_, focusState) {
          final isActive = focusState.isActive || selected;

          return AnimatedContainer(
            duration: AppDurations.normal,
            padding: EdgeInsets.all(scale.space(12, min: 10, max: 14)),
            decoration: AppFocusDecoration.surface(
              isFocused: focusState.isFocused,
              isActive: isActive,
              isSelected: selected,
              backgroundColor: AppColors.backgroundElevated,
              activeBackgroundColor: AppColors.surfaceMuted,
              selectedBackgroundColor: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(
                scale.radius(AppRadii.lg, min: 16, max: 20),
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          color: AppColors.textPrimary,
                          size: scale.sizeOf(20, min: 17, max: 22),
                        ),
                        SizedBox(width: scale.space(8, min: 6, max: 10)),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: scale.text(16, min: 14, max: 17),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: scale.space(6, min: 4, max: 8)),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                        fontSize: scale.text(10.5, min: 10, max: 12),
                      ),
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: scale.sizeOf(24, min: 20, max: 26),
                      height: scale.sizeOf(24, min: 20, max: 26),
                      decoration: const BoxDecoration(
                        color: AppColors.focus,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: AppColors.textPrimary,
                        size: scale.sizeOf(16, min: 14, max: 18),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MoveSelectorFocusIntent extends Intent {
  const _MoveSelectorFocusIntent(this.direction);

  const _MoveSelectorFocusIntent.left() : direction = TraversalDirection.left;

  const _MoveSelectorFocusIntent.right() : direction = TraversalDirection.right;

  const _MoveSelectorFocusIntent.down() : direction = TraversalDirection.down;

  const _MoveSelectorFocusIntent.up() : direction = TraversalDirection.up;

  final TraversalDirection direction;
}
