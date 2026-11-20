part of 'home_screen.dart';

/// TV-first "On this day" browser. It mirrors the Albums and People tabs: a
/// rail of memory "folders" on the left and a grouped asset grid on the right.
class _MemoriesSectionView extends StatelessWidget {
  const _MemoriesSectionView({
    required this.session,
    required this.status,
    required this.errorMessage,
    required this.memories,
    required this.isSidebarOpen,
    required this.menuToggleFocusNode,
    required this.primaryContentFocusNode,
    required this.onToggleSidebar,
    required this.onOpenSidebar,
  });

  final AuthenticatedSession session;
  final LibraryLoadStatus status;
  final String? errorMessage;
  final List<MemorySummary> memories;
  final bool isSidebarOpen;
  final FocusNode menuToggleFocusNode;
  final FocusNode primaryContentFocusNode;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenSidebar;

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      title: 'Memories',
      isSidebarOpen: isSidebarOpen,
      menuToggleFocusNode: menuToggleFocusNode,
      onToggleSidebar: onToggleSidebar,
      child: _AnimatedSectionSwap(
        switchKey: 'memories-${_sectionViewState(status, memories)}',
        child: _MemoriesBrowser(
          session: session,
          status: status,
          errorMessage: errorMessage,
          memories: memories,
          primaryContentFocusNode: primaryContentFocusNode,
          onOpenSidebar: onOpenSidebar,
        ),
      ),
    );
  }
}

class _MemoriesBrowser extends StatefulWidget {
  const _MemoriesBrowser({
    required this.session,
    required this.status,
    required this.errorMessage,
    required this.memories,
    required this.primaryContentFocusNode,
    required this.onOpenSidebar,
  });

  final AuthenticatedSession session;
  final LibraryLoadStatus status;
  final String? errorMessage;
  final List<MemorySummary> memories;
  final FocusNode primaryContentFocusNode;
  final VoidCallback onOpenSidebar;

  @override
  State<_MemoriesBrowser> createState() => _MemoriesBrowserState();
}

class _MemoriesBrowserState extends State<_MemoriesBrowser> {
  final FocusNode _selectedMemoryFocusNode = FocusNode(
    debugLabel: 'memories.selected-memory',
  );
  MemorySummary? _selectedMemory;

  @override
  void dispose() {
    _selectedMemoryFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MemoriesBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.memories.isEmpty) {
      _selectedMemory = null;
      return;
    }
    final stillExists =
        _selectedMemory != null &&
        widget.memories.any((item) => item.id == _selectedMemory!.id);
    if (!stillExists) {
      _selectedMemory = widget.memories.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == LibraryLoadStatus.loading) {
      return const _AssetGridLoadingSkeleton();
    }

    if (widget.status == LibraryLoadStatus.failure) {
      return _InfoPanel(
        title: 'Memories could not load',
        body: widget.errorMessage ?? 'Try again in a moment.',
        accent: AppColors.error,
      );
    }

    if (widget.memories.isEmpty) {
      return const _InfoPanel(
        title: 'No memories yet',
        body: 'Memories appear here as you collect photos on this day in past years. They also require the Memories feature to be enabled on your Immich server.',
        accent: AppColors.textMuted,
      );
    }

    final selected = _selectedMemory ?? widget.memories.first;
    if (_selectedMemory == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedMemory = widget.memories.first);
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = AppScale.of(context);
        return Row(
          children: [
            SizedBox(
              width: _responsiveAlbumRailWidth(constraints.maxWidth, scale),
              child: _MemoryRail(
                memories: widget.memories,
                selectedMemory: selected,
                onMemorySelected: (memory) =>
                    setState(() => _selectedMemory = memory),
                primaryContentFocusNode: widget.primaryContentFocusNode,
                selectedMemoryFocusNode: _selectedMemoryFocusNode,
                onOpenDrawer: widget.onOpenSidebar,
              ),
            ),
            SizedBox(width: scale.space(AppSpacing.xl, min: 24, max: 32)),
            Expanded(child: _buildMemoryContent(selected)),
          ],
        );
      },
    );
  }

  Widget _buildMemoryContent(MemorySummary memory) {
    if (memory.assets.isEmpty) {
      return _InfoPanel(
        title: 'No photos in this memory',
        body: 'This memory does not contain any photos that can be displayed yet.',
        accent: AppColors.textMuted,
      );
    }

    return _GroupedAssetSectionList(
      session: widget.session,
      assets: memory.assets,
      hasMore: false,
      isLoadingMore: false,
      storageKey: 'memory-list-${memory.id}',
      onLoadMore: () {},
      onOpenSidebar: widget.onOpenSidebar,
      onMoveLeftFromGrid: () => _selectedMemoryFocusNode.requestFocus(),
      headingTitle: memory.title,
      headingSubtitle:
          '${_formatMemoryDate(memory.memoryAt)} · '
          '${memory.assets.length} ${memory.assets.length == 1 ? 'photo' : 'photos'}',
    );
  }
}

String _formatMemoryDate(DateTime date) {
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  if (date.month < 1 || date.month > 12) {
    return '${date.year}';
  }
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class _MemoryRail extends StatelessWidget {
  const _MemoryRail({
    required this.memories,
    required this.selectedMemory,
    required this.onMemorySelected,
    required this.primaryContentFocusNode,
    required this.selectedMemoryFocusNode,
    required this.onOpenDrawer,
  });

  final List<MemorySummary> memories;
  final MemorySummary selectedMemory;
  final ValueChanged<MemorySummary> onMemorySelected;
  final FocusNode primaryContentFocusNode;
  final FocusNode selectedMemoryFocusNode;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    return ListView.separated(
      key: const PageStorageKey<String>('memory-rail'),
      itemCount: memories.length,
      separatorBuilder: (_, _) => SizedBox(
        height: scale.space(AppSpacing.sm, min: 10, max: 12),
      ),
      itemBuilder: (context, index) {
        final memory = memories[index];
        final isSelected = memory.id == selectedMemory.id;
        return _MemorySummaryTile(
          memory: memory,
          isSelected: isSelected,
          focusNode: isSelected
              ? selectedMemoryFocusNode
              : (index == 0 ? primaryContentFocusNode : null),
          onOpenDrawer: onOpenDrawer,
          onPressed: () => onMemorySelected(memory),
        );
      },
    );
  }
}

class _MemorySummaryTile extends StatelessWidget {
  const _MemorySummaryTile({
    required this.memory,
    required this.isSelected,
    required this.onPressed,
    this.focusNode,
    this.onOpenDrawer,
  });

  final MemorySummary memory;
  final bool isSelected;
  final FocusNode? focusNode;
  final VoidCallback? onOpenDrawer;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);

    final tile = TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      builder: (context, focusState) {
        final isActive = isSelected || focusState.isActive;
        return AnimatedContainer(
          duration: AppDurations.normal,
          padding: EdgeInsets.all(
            scale.space(AppSpacing.md, min: 14, max: 18),
          ),
          decoration: AppFocusDecoration.surface(
            isFocused: focusState.isFocused,
            isActive: isActive,
            isSelected: isSelected,
            backgroundColor: const Color(0xFF0D1A21),
            activeBackgroundColor: const Color(0xFF13212A),
            selectedBackgroundColor: AppColors.focus.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(
              scale.radius(AppRadii.lg, min: 18, max: 22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    memory.isBirthday
                        ? Icons.cake_outlined
                        : Icons.auto_awesome_outlined,
                    color: isActive ? AppColors.focus : AppColors.warning,
                    size: scale.sizeOf(18, min: 16, max: 20),
                  ),
                  SizedBox(width: scale.space(AppSpacing.sm, min: 8, max: 10)),
                  Expanded(
                    child: Text(
                      memory.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: scale.text(15, min: 13, max: 16),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: scale.space(AppSpacing.xs, min: 6, max: 8)),
              Text(
                _formatMemoryDate(memory.memoryAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: scale.text(12, min: 11, max: 13),
                ),
              ),
              SizedBox(height: scale.space(4, min: 4, max: 6)),
              Text(
                '${memory.assets.length} ${memory.assets.length == 1 ? 'photo' : 'photos'} · ${memory.subtitle}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontSize: scale.text(11, min: 10, max: 12),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (onOpenDrawer == null || focusNode == null) {
      return tile;
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _OpenDrawerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenDrawerIntent: CallbackAction<_OpenDrawerIntent>(
            onInvoke: (_) {
              onOpenDrawer?.call();
              return null;
            },
          ),
        },
        child: tile,
      ),
    );
  }
}
