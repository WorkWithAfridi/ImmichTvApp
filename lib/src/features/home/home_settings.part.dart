part of 'home_screen.dart';

/// TV-first settings surface for the signed-in profile.
///
/// It reuses the same section frame, menu button, and pill-style selection
/// controls as the library tabs so focus and visual language stay consistent.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.isSidebarOpen,
    required this.primaryContentFocusNode,
    required this.menuToggleFocusNode,
    required this.onToggleSidebar,
    required this.onOpenSidebar,
  });

  final AuthenticatedSession session;
  final bool isSidebarOpen;
  final FocusNode primaryContentFocusNode;
  final FocusNode menuToggleFocusNode;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenSidebar;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFieldFocusNode = FocusNode(
    debugLabel: 'settings.pin.field',
  );
  final FocusNode _pinKeyboardFocusNode = FocusNode(
    debugLabel: 'settings.pin.keyboard',
  );
  final FocusNode _pinOffFocusNode = FocusNode(debugLabel: 'settings.pin.off');
  final FocusNode _pinOnFocusNode = FocusNode(debugLabel: 'settings.pin.on');
  final FocusNode _pinCancelFocusNode = FocusNode(
    debugLabel: 'settings.pin.cancel',
  );
  final FocusNode _pinSaveFocusNode = FocusNode(
    debugLabel: 'settings.pin.save',
  );
  final FocusNode _hlsOffFocusNode = FocusNode(debugLabel: 'settings.hls.off');
  final FocusNode _hlsOnFocusNode = FocusNode(debugLabel: 'settings.hls.on');
  bool _isEnrollingPin = false;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    context.read<SettingsCubit>().load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.primaryContentFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFieldFocusNode.dispose();
    _pinKeyboardFocusNode.dispose();
    _pinOffFocusNode.dispose();
    _pinOnFocusNode.dispose();
    _pinCancelFocusNode.dispose();
    _pinSaveFocusNode.dispose();
    _hlsOffFocusNode.dispose();
    _hlsOnFocusNode.dispose();
    super.dispose();
  }

  void _startEnrollingPin() {
    setState(() {
      _isEnrollingPin = true;
      _pinError = null;
      _pinController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pinFieldFocusNode.requestFocus();
      }
    });
  }

  void _cancelEnrollingPin() {
    setState(() {
      _isEnrollingPin = false;
      _pinError = null;
      _pinController.clear();
    });
    _focusActivePinToggle();
  }

  void _focusActivePinToggle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final enabled = context.read<SettingsCubit>().state.pinEnabled;
      (enabled ? _pinOnFocusNode : _pinOffFocusNode).requestFocus();
    });
  }

  Future<void> _savePin() async {
    final pin = _pinController.text;
    if (pin.length != 4) {
      setState(() => _pinError = 'Enter a 4-digit PIN.');
      return;
    }
    final saved = await context.read<SettingsCubit>().setPinEnabled(
      true,
      pin: pin,
    );
    if (!mounted) {
      return;
    }
    if (saved) {
      setState(() {
        _isEnrollingPin = false;
        _pinError = null;
        _pinController.clear();
      });
      _focusActivePinToggle();
    } else {
      setState(() => _pinError = 'That PIN could not be saved.');
    }
  }

  Future<void> _handlePinToggle(bool enabled) async {
    if (enabled) {
      _startEnrollingPin();
      return;
    }
    await context.read<SettingsCubit>().setPinEnabled(false);
    if (mounted) {
      setState(() => _isEnrollingPin = false);
    }
  }

  /// Arrow keys move between the settings controls. From the leftmost control,
  /// left opens the sidebar, matching the other library tabs.
  KeyEventResult _handleArrowKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isHorizontal =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final isVertical =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    if (!isHorizontal && !isVertical) {
      return KeyEventResult.ignored;
    }

    final nodes = <FocusNode>[
      _pinOffFocusNode,
      _pinOnFocusNode,
      if (_isEnrollingPin) _pinCancelFocusNode,
      if (_isEnrollingPin) _pinSaveFocusNode,
      _hlsOffFocusNode,
      _hlsOnFocusNode,
    ];
    final currentIndex = nodes.indexWhere((node) => node.hasFocus);
    final forward =
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown;

    if (currentIndex < 0) {
      // The PIN field is read-only, so arrow keys should move focus to the
      // enrollment actions instead of nudging the text cursor.
      if (_isEnrollingPin && _pinFieldFocusNode.hasFocus) {
        (forward ? _pinSaveFocusNode : _pinCancelFocusNode).requestFocus();
        return KeyEventResult.handled;
      }
      // Focus is still on the content container. Send it to the first control
      // so a single arrow press lands on a button the remote can activate.
      if (widget.primaryContentFocusNode.hasFocus) {
        (forward ? nodes.first : nodes.last).requestFocus();
        return KeyEventResult.handled;
      }
      // Otherwise the on-screen keyboard owns the arrows.
      return KeyEventResult.ignored;
    }

    final nextIndex = currentIndex + (forward ? 1 : -1);
    if (nextIndex < 0 || nextIndex >= nodes.length) {
      if (!forward && currentIndex == 0) {
        widget.onOpenSidebar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    nodes[nextIndex].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          previous.isLoaded != current.isLoaded ||
          previous.pinEnabled != current.pinEnabled ||
          previous.message != current.message ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        if (!_isEnrollingPin && state.isLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            (state.pinEnabled ? _pinOnFocusNode : _pinOffFocusNode)
                .requestFocus();
          });
        }
        final messenger = ScaffoldMessenger.maybeOf(context);
        final text = state.errorMessage ?? state.message;
        if (messenger != null && text != null) {
          messenger.showSnackBar(SnackBar(content: Text(text)));
          context.read<SettingsCubit>().clearMessage();
        }
      },
      child: _SectionFrame(
        title: 'Settings',
        isSidebarOpen: widget.isSidebarOpen,
        menuToggleFocusNode: widget.menuToggleFocusNode,
        onToggleSidebar: widget.onToggleSidebar,
        child: Focus(
          focusNode: widget.primaryContentFocusNode,
          onKeyEvent: _handleArrowKey,
          child: SingleChildScrollView(
            child: BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, state) {
                if (!state.isLoaded) {
                  return _SettingsStatusPanel(
                    message: state.errorMessage ?? 'Loading your settings…',
                    isError: state.errorMessage != null,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsInfoCard(
                      label: 'Signed in as',
                      value: widget.session.user.email,
                    ),
                    SizedBox(height: _settingsSectionSpacing(context)),
                    _SettingsGroupLabel(label: 'SECURITY'),
                    SizedBox(height: _settingsChipSpacing(context)),
                    Text(
                      'Profile PIN',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: AppScale.of(
                          context,
                        ).text(20, min: 17, max: 22),
                      ),
                    ),
                    SizedBox(height: _settingsChipSpacing(context) / 2),
                    Text(
                      state.pinEnabled
                          ? 'A PIN is required when switching to this profile.'
                          : 'No PIN required when switching to this profile.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: AppScale.of(
                          context,
                        ).text(14, min: 12, max: 16),
                      ),
                    ),
                    SizedBox(height: _settingsChipSpacing(context)),
                    _PinToggleSelector(
                      enabled: state.pinEnabled,
                      isBusy: state.isBusy,
                      offFocusNode: _pinOffFocusNode,
                      onFocusNode: _pinOnFocusNode,
                      onChanged: _handlePinToggle,
                    ),
                    if (_isEnrollingPin) ...[
                      SizedBox(height: _settingsSectionSpacing(context)),
                      _PinEnrollmentCard(
                        pinController: _pinController,
                        pinFieldFocusNode: _pinFieldFocusNode,
                        pinKeyboardFocusNode: _pinKeyboardFocusNode,
                        cancelFocusNode: _pinCancelFocusNode,
                        saveFocusNode: _pinSaveFocusNode,
                        errorMessage: _pinError,
                        isBusy: state.isBusy,
                        onPinChanged: (_) {
                          if (_pinError != null) {
                            setState(() => _pinError = null);
                          }
                        },
                        onSave: _savePin,
                        onCancel: _cancelEnrollingPin,
                      ),
                    ],
                    SizedBox(height: _settingsSectionSpacing(context)),
                    const _SettingsGroupLabel(label: 'PLAYBACK'),
                    SizedBox(height: _settingsChipSpacing(context)),
                    Text(
                      'Adaptive streaming (HLS)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: AppScale.of(
                          context,
                        ).text(20, min: 17, max: 22),
                      ),
                    ),
                    SizedBox(height: _settingsChipSpacing(context) / 2),
                    Text(
                      'Alpha Immich feature (v3+). Uses adaptive quality when available and falls back to regular playback.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: AppScale.of(
                          context,
                        ).text(14, min: 12, max: 16),
                      ),
                    ),
                    SizedBox(height: _settingsChipSpacing(context)),
                    _PinToggleSelector(
                      enabled: state.hlsEnabled,
                      isBusy: state.isBusy,
                      offFocusNode: _hlsOffFocusNode,
                      onFocusNode: _hlsOnFocusNode,
                      onChanged: (enabled) =>
                          context.read<SettingsCubit>().setHlsEnabled(enabled),
                    ),
                    SizedBox(height: _settingsSectionSpacing(context)),
                    const _SettingsGroupLabel(label: 'SERVER'),
                    SizedBox(height: _settingsChipSpacing(context)),
                    _SettingsInfoCard(
                      label: 'Immich version',
                      value: widget.session.capabilities.versionLabel,
                    ),
                    SizedBox(height: _settingsChipSpacing(context)),
                    _SettingsInfoCard(
                      label: 'Available features',
                      value: _serverFeatureSummary(widget.session.capabilities),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String _serverFeatureSummary(ServerCapabilities capabilities) {
  final labels = <String>[
    if (capabilities.supports(ServerFeature.memories)) 'Memories',
    if (capabilities.supports(ServerFeature.smartSearch)) 'Smart search',
    if (capabilities.supports(ServerFeature.map)) 'Places',
    if (capabilities.supports(ServerFeature.hlsVideo)) 'Adaptive video',
  ];
  return labels.isEmpty ? 'Basic browsing' : labels.join(' · ');
}

double _settingsSectionSpacing(BuildContext context) {
  final scale = AppScale.of(context);
  return scale.space(AppSpacing.lg, min: 18, max: 24);
}

double _settingsChipSpacing(BuildContext context) {
  final scale = AppScale.of(context);
  return scale.space(AppSpacing.sm, min: 10, max: 12);
}

class _SettingsInfoCard extends StatelessWidget {
  const _SettingsInfoCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);

    return Container(
      padding: EdgeInsets.all(scale.space(18, min: 14, max: 20)),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(
          scale.radius(AppRadii.lg, min: 16, max: 20),
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_outline_rounded,
            color: Colors.white,
            size: scale.sizeOf(24, min: 20, max: 26),
          ),
          SizedBox(width: scale.space(AppSpacing.md, min: 12, max: 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: scale.text(11, min: 10, max: 12),
                  ),
                ),
                SizedBox(height: scale.space(4, min: 4, max: 6)),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: scale.text(16, min: 14, max: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroupLabel extends StatelessWidget {
  const _SettingsGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);

    return Row(
      children: [
        Icon(
          Icons.shield_outlined,
          color: AppColors.textSecondary,
          size: scale.sizeOf(18, min: 16, max: 20),
        ),
        SizedBox(width: scale.space(AppSpacing.xs, min: 6, max: 8)),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            fontSize: scale.text(12, min: 11, max: 14),
          ),
        ),
      ],
    );
  }
}

/// Two focusable pills, mirroring [_AssetSortSelector], so remote users can
/// move between options with the arrows and activate with enter/select.
class _PinToggleSelector extends StatelessWidget {
  const _PinToggleSelector({
    required this.enabled,
    required this.isBusy,
    required this.offFocusNode,
    required this.onFocusNode,
    required this.onChanged,
  });

  final bool enabled;
  final bool isBusy;
  final FocusNode offFocusNode;
  final FocusNode onFocusNode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);

    return FocusTraversalGroup(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PinToggleChip(
            label: 'Off',
            isSelected: !enabled,
            enabled: !isBusy,
            focusNode: offFocusNode,
            onPressed: () => onChanged(false),
          ),
          SizedBox(width: scale.space(AppSpacing.xs, min: 8, max: 10)),
          _PinToggleChip(
            label: 'On',
            isSelected: enabled,
            enabled: !isBusy,
            focusNode: onFocusNode,
            onPressed: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _PinToggleChip extends StatelessWidget {
  const _PinToggleChip({
    required this.label,
    required this.isSelected,
    required this.enabled,
    required this.focusNode,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final bool enabled;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);

    return TvFocusable(
      focusNode: focusNode,
      enabled: enabled,
      onPressed: enabled ? onPressed : null,
      builder: (context, focusState) {
        return AnimatedContainer(
          duration: AppDurations.normal,
          padding: EdgeInsets.symmetric(
            horizontal: scale.space(AppSpacing.lg, min: 20, max: 28),
            vertical: scale.space(AppSpacing.sm, min: 10, max: 12),
          ),
          decoration: AppFocusDecoration.surface(
            isFocused: focusState.isFocused,
            isActive: focusState.isActive,
            isSelected: isSelected,
            backgroundColor: AppColors.panel,
            activeBackgroundColor: AppColors.panelActive,
            selectedBackgroundColor: AppColors.focus.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(
              scale.radius(AppRadii.pill, min: 999, max: 999),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected)
                Padding(
                  padding: EdgeInsets.only(
                    right: scale.space(AppSpacing.xs, min: 6, max: 8),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: scale.sizeOf(16, min: 14, max: 18),
                  ),
                ),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontSize: scale.text(14, min: 12, max: 15),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PinEnrollmentCard extends StatelessWidget {
  const _PinEnrollmentCard({
    required this.pinController,
    required this.pinFieldFocusNode,
    required this.pinKeyboardFocusNode,
    required this.cancelFocusNode,
    required this.saveFocusNode,
    required this.errorMessage,
    required this.isBusy,
    required this.onPinChanged,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController pinController;
  final FocusNode pinFieldFocusNode;
  final FocusNode pinKeyboardFocusNode;
  final FocusNode cancelFocusNode;
  final FocusNode saveFocusNode;
  final String? errorMessage;
  final bool isBusy;
  final ValueChanged<String> onPinChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);

    return Container(
      padding: EdgeInsets.all(scale.space(18, min: 14, max: 20)),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(
          scale.radius(AppRadii.lg, min: 16, max: 20),
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create a 4-digit PIN',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: scale.text(18, min: 16, max: 20),
            ),
          ),
          SizedBox(height: scale.space(6, min: 4, max: 8)),
          Text(
            'You will need this PIN whenever you switch back to this profile.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontSize: scale.text(14, min: 12, max: 16),
            ),
          ),
          SizedBox(height: scale.space(16, min: 12, max: 18)),
          TextField(
            controller: pinController,
            focusNode: pinFieldFocusNode,
            readOnly: true,
            obscureText: true,
            obscuringCharacter: '*',
            showCursor: true,
            textAlign: TextAlign.center,
            enabled: !isBusy,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            style: (theme.textTheme.titleMedium ?? theme.textTheme.bodyLarge)
                ?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: scale.text(22, min: 18, max: 26),
                  letterSpacing: 6,
                ),
            decoration: const InputDecoration(
              labelText: 'PIN',
              hintText: '0000',
              counterText: '',
            ),
          ),
          SizedBox(height: scale.space(12, min: 10, max: 14)),
          OnScreenKeyboard(
            controller: pinController,
            focusNode: pinFieldFocusNode,
            firstKeyFocusNode: pinKeyboardFocusNode,
            type: OnScreenKeyboardType.numeric,
            enabled: !isBusy,
            allowDecimal: false,
            showDecimalButton: false,
            showDoneButton: false,
            maxLength: 4,
            onChanged: onPinChanged,
          ),
          if (errorMessage != null) ...[
            SizedBox(height: scale.space(AppSpacing.sm, min: 10, max: 12)),
            Text(
              errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
          SizedBox(height: scale.space(AppSpacing.md, min: 14, max: 16)),
          FocusTraversalGroup(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PinActionChip(
                  label: 'Cancel',
                  isSelected: false,
                  enabled: !isBusy,
                  focusNode: cancelFocusNode,
                  onPressed: onCancel,
                ),
                SizedBox(width: scale.space(AppSpacing.sm, min: 10, max: 12)),
                _PinActionChip(
                  label: 'Save PIN',
                  isSelected: true,
                  enabled: !isBusy,
                  focusNode: saveFocusNode,
                  onPressed: onSave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinActionChip extends StatelessWidget {
  const _PinActionChip({
    required this.label,
    required this.isSelected,
    required this.enabled,
    required this.focusNode,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final bool enabled;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);

    return TvFocusable(
      focusNode: focusNode,
      enabled: enabled,
      onPressed: enabled ? onPressed : null,
      builder: (context, focusState) {
        return AnimatedContainer(
          duration: AppDurations.normal,
          padding: EdgeInsets.symmetric(
            horizontal: scale.space(AppSpacing.lg, min: 20, max: 28),
            vertical: scale.space(AppSpacing.sm, min: 10, max: 12),
          ),
          decoration: AppFocusDecoration.surface(
            isFocused: focusState.isFocused,
            isActive: focusState.isActive,
            isSelected: isSelected,
            backgroundColor: AppColors.panel,
            activeBackgroundColor: AppColors.panelActive,
            selectedBackgroundColor: AppColors.focus.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(
              scale.radius(AppRadii.pill, min: 999, max: 999),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: scale.text(14, min: 12, max: 15),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsStatusPanel extends StatelessWidget {
  const _SettingsStatusPanel({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);

    return Container(
      padding: EdgeInsets.all(scale.space(24, min: 18, max: 28)),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(
          scale.radius(AppRadii.lg, min: 16, max: 20),
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
            color: isError ? AppColors.error : AppColors.textSecondary,
            size: scale.sizeOf(32, min: 28, max: 36),
          ),
          SizedBox(height: scale.space(AppSpacing.md, min: 12, max: 16)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isError ? AppColors.error : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
