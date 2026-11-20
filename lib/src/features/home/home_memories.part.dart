part of 'home_screen.dart';

/// TV-first "On this day" browser. It mirrors the Albums and People tabs: a
/// rail of year "folders" on the left and a date-grouped asset grid on the
/// right. Multiple memories from the same year share a single folder.
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
  final FocusNode _selectedYearFocusNode = FocusNode(
    debugLabel: 'memories.selected-year',
  );
  int? _selectedYear;

  @override
  void dispose() {
    _selectedYearFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MemoriesBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.memories.isEmpty) {
      _selectedYear = null;
      return;
    }
    final groups = _groupMemoriesByYear(widget.memories);
    if (_selectedYear == null ||
        !groups.any((group) => group.year == _selectedYear)) {
      _selectedYear = groups.first.year;
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

    final groups = _groupMemoriesByYear(widget.memories);
    final selected = groups.firstWhere(
      (group) => group.year == _selectedYear,
      orElse: () => groups.first,
    );
    if (_selectedYear == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedYear = groups.first.year);
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
              child: _MemoryYearRail(
                groups: groups,
                selectedGroup: selected,
                onYearSelected: (year) =>
                    setState(() => _selectedYear = year),
                primaryContentFocusNode: widget.primaryContentFocusNode,
                selectedYearFocusNode: _selectedYearFocusNode,
                onOpenDrawer: widget.onOpenSidebar,
              ),
            ),
            SizedBox(width: scale.space(AppSpacing.xl, min: 24, max: 32)),
            Expanded(child: _buildYearContent(selected)),
          ],
        );
      },
    );
  }

  Widget _buildYearContent(_MemoryYearGroup group) {
    if (group.assets.isEmpty) {
      return _InfoPanel(
        title: 'No photos in ${group.year}',
        body: 'This year does not contain any photos that can be displayed yet.',
        accent: AppColors.textMuted,
      );
    }

    return _GroupedAssetSectionList(
      session: widget.session,
      assets: group.assets,
      hasMore: false,
      isLoadingMore: false,
      storageKey: 'memory-list-${group.year}',
      onLoadMore: () {},
      onOpenSidebar: widget.onOpenSidebar,
      onMoveLeftFromGrid: () => _selectedYearFocusNode.requestFocus(),
      headingTitle: '${group.year}',
      headingSubtitle:
          '${group.dateLabel} · '
          '${group.assets.length} ${group.assets.length == 1 ? 'photo' : 'photos'}',
    );
  }
}

class _MemoryYearGroup {
  _MemoryYearGroup({
    required this.year,
    required this.memories,
    required this.assets,
  });

  final int year;
  final List<MemorySummary> memories;
  final List<AssetSummary> assets;

  bool get hasBirthday => memories.any((memory) => memory.isBirthday);

  String get dateLabel {
    if (memories.isEmpty) {
      return '';
    }
    final dates = memories.map((memory) => memory.memoryAt).toList()
      ..sort((a, b) => a.compareTo(b));
    final start = dates.first;
    final end = dates.last;
    if (_isSameDay(start, end)) {
      return _formatMemoryDate(start);
    }
    return '${_shortMonth(start.month)} ${start.day} – '
        '${_shortMonth(end.month)} ${end.day}, $year';
  }
}

List<_MemoryYearGroup> _groupMemoriesByYear(List<MemorySummary> memories) {
  final byYear = <int, List<MemorySummary>>{};
  for (final memory in memories) {
    (byYear[memory.memoryAt.year] ??= <MemorySummary>[]).add(memory);
  }

  final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
  return years
      .map((year) {
        final groupedMemories = byYear[year]!;
        final seen = <String>{};
        final assets = <AssetSummary>[];
        for (final memory in groupedMemories) {
          for (final asset in memory.assets) {
            if (seen.add(asset.id)) {
              assets.add(asset);
            }
          }
        }
        assets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return _MemoryYearGroup(
          year: year,
          memories: groupedMemories,
          assets: List<AssetSummary>.unmodifiable(assets),
        );
      })
      .toList(growable: false);
}

String _shortMonth(int month) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (month < 1 || month > 12) {
    return '???';
  }
  return months[month - 1];
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

class _MemoryYearRail extends StatelessWidget {
  const _MemoryYearRail({
    required this.groups,
    required this.selectedGroup,
    required this.onYearSelected,
    required this.primaryContentFocusNode,
    required this.selectedYearFocusNode,
    required this.onOpenDrawer,
  });

  final List<_MemoryYearGroup> groups;
  final _MemoryYearGroup selectedGroup;
  final ValueChanged<int> onYearSelected;
  final FocusNode primaryContentFocusNode;
  final FocusNode selectedYearFocusNode;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    return ListView.separated(
      key: const PageStorageKey<String>('memory-year-rail'),
      itemCount: groups.length,
      separatorBuilder: (_, _) => SizedBox(
        height: scale.space(AppSpacing.sm, min: 10, max: 12),
      ),
      itemBuilder: (context, index) {
        final group = groups[index];
        final isSelected = group.year == selectedGroup.year;
        return _MemoryYearTile(
          group: group,
          isSelected: isSelected,
          focusNode: isSelected
              ? selectedYearFocusNode
              : (index == 0 ? primaryContentFocusNode : null),
          onOpenDrawer: onOpenDrawer,
          onPressed: () => onYearSelected(group.year),
        );
      },
    );
  }
}

class _MemoryYearTile extends StatelessWidget {
  const _MemoryYearTile({
    required this.group,
    required this.isSelected,
    required this.onPressed,
    this.focusNode,
    this.onOpenDrawer,
  });

  final _MemoryYearGroup group;
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
            backgroundColor: AppColors.panel,
            activeBackgroundColor: AppColors.panelActive,
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
                    group.hasBirthday
                        ? Icons.cake_outlined
                        : Icons.folder_open_outlined,
                    color: isActive ? AppColors.focus : AppColors.warning,
                    size: scale.sizeOf(18, min: 16, max: 20),
                  ),
                  SizedBox(width: scale.space(AppSpacing.sm, min: 8, max: 10)),
                  Expanded(
                    child: Text(
                      '${group.year}',
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
                group.dateLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: scale.text(12, min: 11, max: 13),
                ),
              ),
              SizedBox(height: scale.space(4, min: 4, max: 6)),
              Text(
                '${group.assets.length} ${group.assets.length == 1 ? 'photo' : 'photos'} · '
                '${group.memories.length} ${group.memories.length == 1 ? 'memory' : 'memories'}',
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
