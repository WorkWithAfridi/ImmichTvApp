part of 'home_screen.dart';

class _AlbumSectionView extends StatefulWidget {
  const _AlbumSectionView({
    required this.session,
    required this.status,
    required this.errorMessage,
    required this.albums,
    required this.isSidebarOpen,
    required this.menuToggleFocusNode,
    required this.primaryContentFocusNode,
    required this.onToggleSidebar,
    required this.onOpenSidebar,
  });

  final AuthenticatedSession session;
  final LibraryLoadStatus status;
  final String? errorMessage;
  final List<AlbumSummary> albums;
  final bool isSidebarOpen;
  final FocusNode menuToggleFocusNode;
  final FocusNode primaryContentFocusNode;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenSidebar;

  @override
  State<_AlbumSectionView> createState() => _AlbumSectionViewState();
}

class _AlbumSectionViewState extends State<_AlbumSectionView> {
  AssetSortOrder _sortOrder = AssetSortOrder.newestFirst;

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      title: 'Albums',
      isSidebarOpen: widget.isSidebarOpen,
      menuToggleFocusNode: widget.menuToggleFocusNode,
      onToggleSidebar: widget.onToggleSidebar,
      trailing: _AssetSortSelector(
        value: _sortOrder,
        onChanged: (value) => setState(() => _sortOrder = value),
      ),
      child: _AlbumBrowser(
        session: widget.session,
        status: widget.status,
        errorMessage: widget.errorMessage,
        albums: widget.albums,
        primaryContentFocusNode: widget.primaryContentFocusNode,
        onOpenSidebar: widget.onOpenSidebar,
        sortOrder: _sortOrder,
      ),
    );
  }
}

class _AlbumBrowser extends StatefulWidget {
  const _AlbumBrowser({
    required this.session,
    required this.status,
    required this.errorMessage,
    required this.albums,
    required this.primaryContentFocusNode,
    required this.onOpenSidebar,
    required this.sortOrder,
  });

  final AuthenticatedSession session;
  final LibraryLoadStatus status;
  final String? errorMessage;
  final List<AlbumSummary> albums;
  final FocusNode primaryContentFocusNode;
  final VoidCallback onOpenSidebar;
  final AssetSortOrder sortOrder;

  @override
  State<_AlbumBrowser> createState() => _AlbumBrowserState();
}

class _AlbumBrowserState extends State<_AlbumBrowser> {
  static const _albumRefreshInterval = Duration(minutes: 1);

  final FocusNode _selectedAlbumFocusNode = FocusNode(
    debugLabel: 'albums.selected-album',
  );
  AlbumSummary? _selectedAlbum;
  List<AssetSummary> _albumAssets = const [];
  String? _albumAssetsNextPage;
  bool _isLoadingAlbumAssets = false;
  String? _albumAssetsError;
  Timer? _albumRefreshTimer;

  @override
  void dispose() {
    _albumRefreshTimer?.cancel();
    _selectedAlbumFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AlbumBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.albums.isEmpty) {
      _selectedAlbum = null;
      _albumAssets = const [];
      _albumAssetsNextPage = null;
      _albumAssetsError = null;
      _isLoadingAlbumAssets = false;
      return;
    }

    final selectedAlbumStillExists =
        _selectedAlbum != null &&
        widget.albums.any((album) => album.id == _selectedAlbum!.id);
    if (!selectedAlbumStillExists) {
      _selectAlbum(widget.albums.first);
      return;
    }

    if (_selectedAlbum != null) {
      final refreshedSelectedAlbum = widget.albums.firstWhere(
        (album) => album.id == _selectedAlbum!.id,
      );
      if (refreshedSelectedAlbum != _selectedAlbum) {
        _selectedAlbum = refreshedSelectedAlbum;
      }
    }

    if (oldWidget.sortOrder != widget.sortOrder && _selectedAlbum != null) {
      _selectAlbum(_selectedAlbum!);
    }
  }

  Widget _buildBody(BuildContext context) {
    if (widget.status == LibraryLoadStatus.loading) {
      return const _AlbumBrowserLoadingSkeleton();
    }

    if (widget.status == LibraryLoadStatus.failure) {
      return _InfoPanel(
        title: 'Albums are unavailable right now',
        body: widget.errorMessage ?? 'Try again in a moment.',
        accent: AppColors.error,
      );
    }

    if (widget.albums.isEmpty) {
      return const _InfoPanel(
        title: 'No albums yet',
        body: 'Album collections will appear here.',
        accent: AppColors.textMuted,
      );
    }

    final selectedAlbum = _selectedAlbum ?? widget.albums.first;

    if (_selectedAlbum == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectAlbum(widget.albums.first);
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = AppScale.of(context);
        final albumRail = _AlbumRail(
          albums: widget.albums,
          selectedAlbum: selectedAlbum,
          onAlbumSelected: _selectAlbum,
          horizontal: false,
          primaryContentFocusNode: widget.primaryContentFocusNode,
          selectedAlbumFocusNode: _selectedAlbumFocusNode,
          onOpenDrawer: widget.onOpenSidebar,
        );
        final albumContent = _buildAlbumContent(selectedAlbum);

        return Row(
          children: [
            SizedBox(
              width: _responsiveAlbumRailWidth(constraints.maxWidth, scale),
              child: albumRail,
            ),
            SizedBox(width: scale.space(AppSpacing.xl, min: 24, max: 32)),
            Expanded(child: albumContent),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => _buildBody(context);

  void _selectAlbum(AlbumSummary album) {
    _ensureAlbumRefreshPolling();
    setState(() {
      _selectedAlbum = album;
      _albumAssets = const [];
      _albumAssetsNextPage = null;
      _albumAssetsError = null;
      _isLoadingAlbumAssets = false;
    });
    _loadAlbumAssets(album: album, page: null, replace: true);
  }

  Widget _buildAlbumContent(AlbumSummary selectedAlbum) {
    if (_isLoadingAlbumAssets && _albumAssets.isEmpty) {
      return const _AssetGridLoadingSkeleton(
        leadingHeight: 20,
        leadingWidth: 220,
      );
    }

    if (_albumAssetsError != null && _albumAssets.isEmpty) {
      return _InfoPanel(
        title: 'This album could not load',
        body: _albumAssetsError!,
        accent: AppColors.error,
      );
    }

    if (_albumAssets.isEmpty) {
      return _InfoPanel(
        title: 'No assets in ${selectedAlbum.name}',
        body:
            'This album does not contain any assets that can be displayed yet.',
        accent: AppColors.textMuted,
      );
    }

    return _GroupedAssetSectionList(
      session: widget.session,
      assets: _albumAssets,
      hasMore: _albumAssetsNextPage != null && _albumAssetsNextPage!.isNotEmpty,
      isLoadingMore: _isLoadingAlbumAssets && _albumAssets.isNotEmpty,
      storageKey: 'album-list-${selectedAlbum.id}',
      onLoadMore: _loadMoreAlbumAssets,
      onOpenSidebar: widget.onOpenSidebar,
      onMoveLeftFromGrid: () => _selectedAlbumFocusNode.requestFocus(),
      slideshowPageLoader: _fetchMoreForSlideshow,
      hasMoreSlideshowPages: _albumAssetsNextPage?.isNotEmpty ?? false,
      headingTitle: selectedAlbum.name,
      headingSubtitle: '${_albumAssets.length} assets',
    );
  }

  Future<SlideshowPage> _fetchMoreForSlideshow() async {
    final album = _selectedAlbum;
    final page = _albumAssetsNextPage;
    if (album == null ||
        page == null ||
        page.isEmpty ||
        _isLoadingAlbumAssets) {
      return const SlideshowPage(items: [], hasMore: false);
    }

    try {
      final response = await context.read<MediaRepository>().fetchAlbumAssetsPage(
        widget.session,
        albumId: album.id,
        sortOrder: widget.sortOrder,
        page: page,
      );
      final fresh = _dedupeAlbumAssets(_albumAssets, response.items);
      if (!mounted || _selectedAlbum?.id != album.id) {
        return const SlideshowPage(items: [], hasMore: false);
      }
      setState(() {
        _albumAssets = [..._albumAssets, ...fresh];
        _albumAssetsNextPage = response.nextPage;
      });
      return SlideshowPage(items: fresh, hasMore: response.hasMore);
    } catch (_) {
      return const SlideshowPage(items: [], hasMore: false);
    }
  }

  Future<void> _loadMoreAlbumAssets() async {
    final selectedAlbum = _selectedAlbum;
    final nextPage = _albumAssetsNextPage;
    if (selectedAlbum == null || nextPage == null || _isLoadingAlbumAssets) {
      return;
    }

    await _loadAlbumAssets(
      album: selectedAlbum,
      page: nextPage,
      replace: false,
    );
  }

  Future<void> _loadAlbumAssets({
    required AlbumSummary album,
    required String? page,
    required bool replace,
    bool background = false,
  }) async {
    if (_isLoadingAlbumAssets) {
      return;
    }

    if (background) {
      _ensureAlbumRefreshPolling();
    } else {
      setState(() {
        _isLoadingAlbumAssets = true;
        _albumAssetsError = null;
      });
    }

    try {
      final response = await context.read<MediaRepository>().fetchAlbumAssetsPage(
        widget.session,
        albumId: album.id,
        sortOrder: widget.sortOrder,
        page: page,
      );
      if (!mounted || _selectedAlbum?.id != album.id) {
        return;
      }

      final nextAssets = replace
          ? _mergeRefreshedAlbumAssets(
              existing: _albumAssets,
              refreshedFirstPage: response.items,
            )
          : [
              ..._albumAssets,
              ..._dedupeAlbumAssets(_albumAssets, response.items),
            ];
      final hasChanges =
          !_listEquals(_albumAssets, nextAssets) ||
          _albumAssetsNextPage != response.nextPage ||
          _isLoadingAlbumAssets;
      if (!hasChanges && background) {
        return;
      }

      setState(() {
        _albumAssets = nextAssets;
        _albumAssetsNextPage = response.nextPage;
        _isLoadingAlbumAssets = false;
        if (!background) {
          _albumAssetsError = null;
        }
      });
    } catch (error) {
      if (!mounted || _selectedAlbum?.id != album.id) {
        return;
      }

      if (background) {
        return;
      }

      setState(() {
        _isLoadingAlbumAssets = false;
        _albumAssetsError = error is AppException
            ? error.message
            : 'We could not load this album right now.';
      });
    }
  }

  List<AssetSummary> _dedupeAlbumAssets(
    List<AssetSummary> existing,
    List<AssetSummary> incoming,
  ) {
    final existingIds = existing.map((item) => item.id).toSet();
    return incoming
        .where((item) => !existingIds.contains(item.id))
        .toList(growable: false);
  }

  List<AssetSummary> _mergeRefreshedAlbumAssets({
    required List<AssetSummary> existing,
    required List<AssetSummary> refreshedFirstPage,
  }) {
    if (existing.isEmpty) {
      return refreshedFirstPage;
    }

    if (_listEquals(existing, refreshedFirstPage)) {
      return existing;
    }

    final refreshedIds = refreshedFirstPage.map((item) => item.id).toSet();
    return List<AssetSummary>.unmodifiable([
      ...refreshedFirstPage,
      ...existing.where((item) => !refreshedIds.contains(item.id)),
    ]);
  }

  bool _listEquals(List<AssetSummary> left, List<AssetSummary> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  void _ensureAlbumRefreshPolling() {
    _albumRefreshTimer ??= Timer.periodic(_albumRefreshInterval, (_) {
      final selectedAlbum = _selectedAlbum;
      if (!mounted ||
          selectedAlbum == null ||
          widget.status != LibraryLoadStatus.success) {
        return;
      }
      unawaited(
        _loadAlbumAssets(
          album: selectedAlbum,
          page: null,
          replace: true,
          background: true,
        ),
      );
    });
  }
}

class _AlbumRail extends StatelessWidget {
  const _AlbumRail({
    required this.albums,
    required this.selectedAlbum,
    required this.onAlbumSelected,
    required this.horizontal,
    required this.primaryContentFocusNode,
    required this.selectedAlbumFocusNode,
    required this.onOpenDrawer,
  });

  final List<AlbumSummary> albums;
  final AlbumSummary selectedAlbum;
  final ValueChanged<AlbumSummary> onAlbumSelected;
  final bool horizontal;
  final FocusNode primaryContentFocusNode;
  final FocusNode selectedAlbumFocusNode;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    return ListView.separated(
      key: PageStorageKey<String>(
        horizontal ? 'album-rail-horizontal' : 'album-rail-vertical',
      ),
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      itemCount: albums.length,
      separatorBuilder: (_, _) => SizedBox(
        width: horizontal ? scale.space(AppSpacing.sm, min: 10, max: 12) : 0,
        height: horizontal ? 0 : scale.space(AppSpacing.sm, min: 10, max: 12),
      ),
      itemBuilder: (context, index) {
        final album = albums[index];
        return SizedBox(
          width: horizontal ? scale.sizeOf(196, min: 176, max: 204) : null,
          child: _AlbumSummaryTile(
            album: album,
            isSelected: album.id == selectedAlbum.id,
            compact: horizontal,
            focusNode: album.id == selectedAlbum.id
                ? selectedAlbumFocusNode
                : (index == 0 ? primaryContentFocusNode : null),
            onOpenDrawer: !horizontal ? onOpenDrawer : null,
            onPressed: () => onAlbumSelected(album),
          ),
        );
      },
    );
  }
}

class _AlbumSummaryTile extends StatefulWidget {
  const _AlbumSummaryTile({
    required this.album,
    required this.isSelected,
    this.compact = false,
    this.focusNode,
    this.onOpenDrawer,
    required this.onPressed,
  });

  final AlbumSummary album;
  final bool isSelected;
  final bool compact;
  final FocusNode? focusNode;
  final VoidCallback? onOpenDrawer;
  final VoidCallback onPressed;

  @override
  State<_AlbumSummaryTile> createState() => _AlbumSummaryTileState();
}

class _AlbumSummaryTileState extends State<_AlbumSummaryTile> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppScale.of(context);
    final tile = TvFocusable(
      focusNode: widget.focusNode,
      onPressed: widget.onPressed,
      builder: (context, focusState) {
        final isFocused = focusState.isFocused;
        final isActive = widget.isSelected || focusState.isActive;

        return AnimatedContainer(
          duration: AppDurations.normal,
          padding: EdgeInsets.all(
            scale.space(
              widget.compact ? AppSpacing.sm : AppSpacing.md,
              min: widget.compact ? 12 : 14,
              max: widget.compact ? 14 : 18,
            ),
          ),
          decoration: AppFocusDecoration.surface(
            isFocused: isFocused,
            isActive: isActive,
            isSelected: widget.isSelected,
            backgroundColor: AppColors.panel,
            activeBackgroundColor: AppColors.panelActive,
            borderRadius: BorderRadius.circular(
              scale.radius(
                AppRadii.lg,
                min: widget.compact ? 18 : 20,
                max: widget.compact ? 20 : 24,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.album.name,
                maxLines: widget.compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: scale.text(
                    widget.compact ? 14 : 15,
                    min: 12,
                    max: widget.compact ? 14 : 15,
                  ),
                  height: 1.2,
                ),
              ),
              SizedBox(
                height: scale.space(
                  AppSpacing.xs,
                  min: 4,
                  max: 6,
                ),
              ),
              Text(
                '${widget.album.assetCount} assets',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: scale.text(
                    widget.compact ? 10 : 11,
                    min: 9,
                    max: widget.compact ? 10 : 11,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (widget.onOpenDrawer == null) {
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
              widget.onOpenDrawer?.call();
              return null;
            },
          ),
        },
        child: tile,
      ),
    );
  }
}
