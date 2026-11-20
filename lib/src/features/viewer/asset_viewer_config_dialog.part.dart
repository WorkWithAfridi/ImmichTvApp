part of 'asset_viewer_screen.dart';

class _SlideshowConfigDialog extends StatefulWidget {
  const _SlideshowConfigDialog({
    required this.durationOptions,
    required this.photoCount,
    required this.currentAssetIsVideo,
    required this.totalAssetCount,
    required this.initialDurationSeconds,
  });

  final List<int> durationOptions;
  final int photoCount;
  final bool currentAssetIsVideo;
  final int totalAssetCount;
  final int initialDurationSeconds;

  @override
  State<_SlideshowConfigDialog> createState() => _SlideshowConfigDialogState();
}

class _SlideshowConfigDialogState extends State<_SlideshowConfigDialog> {
  late int _selectedSeconds;
  late final List<FocusNode> _focusNodes;
  static const _durationItemExtent = 124.0;

  late final FocusNode _closeFocusNode;
  late final FocusNode _cancelFocusNode;
  late final ScrollController _durationScrollController;

  @override
  void initState() {
    super.initState();
    _selectedSeconds = widget.durationOptions.contains(
      widget.initialDurationSeconds,
    )
        ? widget.initialDurationSeconds
        : widget.durationOptions.first;
    _focusNodes = List<FocusNode>.generate(
      widget.durationOptions.length,
      (index) => FocusNode(debugLabel: 'slideshow-duration-$index'),
    );
    _closeFocusNode = FocusNode(debugLabel: 'slideshow-close');
    _cancelFocusNode = FocusNode(debugLabel: 'slideshow-cancel');
    _durationScrollController = ScrollController();
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _closeFocusNode.dispose();
    _cancelFocusNode.dispose();
    _durationScrollController.dispose();
    super.dispose();
  }

  List<FocusNode> get _navigationOrder => <FocusNode>[
    ..._focusNodes,
    _cancelFocusNode,
    _closeFocusNode,
  ];

  int get _currentFocusIndex {
    final index = _navigationOrder.indexWhere((node) => node.hasFocus);
    return index < 0 ? 0 : index;
  }

  void _focusDuration(int index) {
    final count = _focusNodes.length;
    if (count == 0) {
      return;
    }
    final target = index.clamp(0, count - 1);
    _focusNodes[target].requestFocus();
    _scrollDurationIntoView(target);
  }

  /// Left/right stay inside the duration row.
  void _moveHorizontally(int delta) {
    final current = _currentFocusIndex;
    if (current >= _focusNodes.length) {
      _focusDuration(delta < 0 ? _focusNodes.length - 1 : 0);
      return;
    }
    final count = _focusNodes.length;
    _focusDuration((current + delta + count) % count);
  }

  /// Up/down move between the duration row and the buttons below it.
  void _moveVertically(int delta) {
    final current = _currentFocusIndex;
    final cancelIndex = _focusNodes.length;
    final closeIndex = cancelIndex + 1;

    if (delta > 0) {
      _cancelFocusNode.requestFocus();
      return;
    }

    if (current == cancelIndex) {
      _focusDuration(_selectedDurationIndex);
    } else if (current == closeIndex) {
      _focusDuration(_selectedDurationIndex);
    } else {
      _closeFocusNode.requestFocus();
    }
  }

  int get _selectedDurationIndex {
    final index = widget.durationOptions.indexOf(_selectedSeconds);
    return index < 0 ? 0 : index;
  }

  void _scrollDurationIntoView(int index) {
    if (!_durationScrollController.hasClients) {
      return;
    }
    final maxScroll =
        _durationScrollController.position.maxScrollExtent;
    final target = (index * _durationItemExtent).clamp(0.0, maxScroll);
    _durationScrollController.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            _DialogHorizontalIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            _DialogHorizontalIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            _DialogVerticalIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            _DialogVerticalIntent(1),
        const SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DialogHorizontalIntent: CallbackAction<_DialogHorizontalIntent>(
            onInvoke: (intent) {
              _moveHorizontally(intent.delta);
              return null;
            },
          ),
          _DialogVerticalIntent: CallbackAction<_DialogVerticalIntent>(
            onInvoke: (intent) {
              _moveVertically(intent.delta);
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Dialog(
          backgroundColor: AppColors.panel,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xl,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            side: const BorderSide(color: AppColors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Start slideshow',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      TvFocusable(
                        focusNode: _closeFocusNode,
                        onPressed: () => Navigator.of(context).pop(),
                        builder: (context, focusState) {
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              color: focusState.isFocused
                                  ? AppColors.focus.withValues(alpha: 0.24)
                                  : Colors.white.withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: focusState.isFocused
                                    ? AppColors.focus
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(AppSpacing.sm),
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.currentAssetIsVideo
                        ? 'Videos are skipped. Playback starts from the first photo in this set.'
                        : 'Choose how long each photo stays on screen. Selecting an interval starts playback immediately.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '$photoLabel · ${widget.totalAssetCount} items in this view',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Interval',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 104,
                    child: ListView.builder(
                      controller: _durationScrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      itemCount: widget.durationOptions.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: _SlideshowDurationOption(
                            seconds: widget.durationOptions[index],
                            isSelected:
                                widget.durationOptions[index] ==
                                _selectedSeconds,
                            focusNode: _focusNodes[index],
                            autofocus: index == 0,
                            onPressed: () => Navigator.of(
                              context,
                            ).pop(widget.durationOptions[index]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SlideshowDialogButton(
                    label: 'Cancel',
                    focusNode: _cancelFocusNode,
                    expanded: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Left/Right: interval · Up/Down: buttons · Enter: select · Esc: cancel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get photoLabel =>
      '${widget.photoCount} ${widget.photoCount == 1 ? 'photo' : 'photos'}';
}

class _DialogHorizontalIntent extends Intent {
  const _DialogHorizontalIntent(this.delta);

  final int delta;
}

class _DialogVerticalIntent extends Intent {
  const _DialogVerticalIntent(this.delta);

  final int delta;
}

class _SlideshowDialogButton extends StatelessWidget {
  const _SlideshowDialogButton({
    required this.label,
    required this.focusNode,
    required this.onPressed,
    this.expanded = false,
  });

  final String label;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: expanded ? double.infinity : null,
      child: TvFocusable(
        focusNode: focusNode,
        onPressed: onPressed,
        builder: (context, focusState) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: focusState.isFocused
                  ? AppColors.focus.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: focusState.isFocused
                    ? AppColors.focus
                    : Colors.white.withValues(alpha: 0.14),
                width: focusState.isFocused ? 2.4 : 1.2,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
