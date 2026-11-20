part of 'home_screen.dart';

/// Places browser: a rail of cities on the left and a date-grouped asset grid
/// for the selected city on the right.
class _PlacesSectionView extends StatelessWidget {
  const _PlacesSectionView({
    required this.session,
    required this.status,
    required this.errorMessage,
    required this.places,
    required this.isSidebarOpen,
    required this.menuToggleFocusNode,
    required this.primaryContentFocusNode,
    required this.onToggleSidebar,
    required this.onOpenSidebar,
  });

  final AuthenticatedSession session;
  final LibraryLoadStatus status;
  final String? errorMessage;
  final List<PlaceSummary> places;
  final bool isSidebarOpen;
  final FocusNode menuToggleFocusNode;
  final FocusNode primaryContentFocusNode;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenSidebar;

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      title: 'Places',
      isSidebarOpen: isSidebarOpen,
      menuToggleFocusNode: menuToggleFocusNode,
      onToggleSidebar: onToggleSidebar,
      child: _AnimatedSectionSwap(
        switchKey: 'places-${_sectionViewState(status, places)}',
        child: _PlacesBrowser(
          session: session,
          status: status,
          errorMessage: errorMessage,
          places: places,
          primaryContentFocusNode: primaryContentFocusNode,
          onOpenSidebar: onOpenSidebar,
        ),
      ),
    );
  }
}

class _PlacesBrowser extends StatefulWidget {
  const _PlacesBrowser({
    required this.session,
    required this.status,
    required this.errorMessage,
    required this.places,
    required this.primaryContentFocusNode,
    required this.onOpenSidebar,
  });

  final AuthenticatedSession session;
  final LibraryLoadStatus status;
  final String? errorMessage;
  final List<PlaceSummary> places;
  final FocusNode primaryContentFocusNode;
  final VoidCallback onOpenSidebar;

  @override
  State<_PlacesBrowser> createState() => _PlacesBrowserState();
}

class _PlacesBrowserState extends State<_PlacesBrowser> {
  static const _pageSize = 60;

  final FocusNode _selectedPlaceFocusNode = FocusNode(
    debugLabel: 'places.selected-place',
  );
  PlaceSummary? _selectedPlace;
  List<AssetSummary> _assets = const [];
  String? _nextPage;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _selectedPlaceFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PlacesBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.places.isEmpty) {
      _selectedPlace = null;
      _assets = const [];
      _nextPage = null;
      _error = null;
      return;
    }
    final stillExists =
        _selectedPlace != null &&
        widget.places.any((place) => place.id == _selectedPlace!.id);
    if (!stillExists) {
      _selectPlace(widget.places.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == LibraryLoadStatus.loading) {
      return const _AssetGridLoadingSkeleton();
    }
    if (widget.status == LibraryLoadStatus.failure) {
      return _InfoPanel(
        title: 'Places could not load',
        body: widget.errorMessage ?? 'Try again in a moment.',
        accent: AppColors.error,
      );
    }
    if (widget.places.isEmpty) {
      return const _InfoPanel(
        title: 'No places yet',
        body: 'Photos with location data will appear here. The Places feature must also be enabled on your Immich server.',
        accent: AppColors.textMuted,
      );
    }

    final selected = _selectedPlace ?? widget.places.first;
    if (_selectedPlace == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectPlace(widget.places.first);
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
              child: _PlaceRail(
                session: widget.session,
                places: widget.places,
                selectedPlace: selected,
                onPlaceSelected: _selectPlace,
                primaryContentFocusNode: widget.primaryContentFocusNode,
                selectedPlaceFocusNode: _selectedPlaceFocusNode,
                onOpenDrawer: widget.onOpenSidebar,
              ),
            ),
            SizedBox(width: scale.space(AppSpacing.xl, min: 24, max: 32)),
            Expanded(child: _buildPlaceContent(selected)),
          ],
        );
      },
    );
  }

  void _selectPlace(PlaceSummary place) {
    setState(() {
      _selectedPlace = place;
      _assets = const [];
      _nextPage = null;
      _error = null;
      _isLoading = false;
    });
    unawaited(_loadPlace(place: place, page: null, replace: true));
  }

  Widget _buildPlaceContent(PlaceSummary place) {
    if (_isLoading && _assets.isEmpty) {
      return const _AssetGridLoadingSkeleton(
        leadingHeight: 20,
        leadingWidth: 220,
      );
    }
    if (_error != null && _assets.isEmpty) {
      return _InfoPanel(
        title: 'This place could not load',
        body: _error!,
        accent: AppColors.error,
      );
    }
    if (_assets.isEmpty) {
      return _InfoPanel(
        title: 'No photos in ${place.city}',
        body: 'There are no photos with this location that can be displayed yet.',
        accent: AppColors.textMuted,
      );
    }

    return _GroupedAssetSectionList(
      session: widget.session,
      assets: _assets,
      hasMore: _nextPage?.isNotEmpty ?? false,
      isLoadingMore: _isLoading && _assets.isNotEmpty,
      storageKey: 'place-list-${place.id}',
      onLoadMore: () => _loadPlace(
        place: place,
        page: _nextPage,
        replace: false,
      ),
      onOpenSidebar: widget.onOpenSidebar,
      onMoveLeftFromGrid: () => _selectedPlaceFocusNode.requestFocus(),
      slideshowPageLoader: () => _fetchMoreForSlideshow(place),
      hasMoreSlideshowPages: _nextPage?.isNotEmpty ?? false,
      headingTitle: place.city,
      headingSubtitle: place.subtitle.isEmpty ? null : place.subtitle,
    );
  }

  Future<void> _loadPlace({
    required PlaceSummary place,
    required String? page,
    required bool replace,
  }) async {
    if (_isLoading) {
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await context.read<MediaRepository>().fetchPlaceAssetsPage(
        widget.session,
        place: place,
        page: page,
        pageSize: _pageSize,
      );
      if (!mounted || _selectedPlace?.id != place.id) {
        return;
      }
      final incoming = response.items;
      final next = replace
          ? incoming
          : [
              ..._assets,
              ...incoming.where(
                (asset) => !_assets.any((item) => item.id == asset.id),
              ),
            ];
      setState(() {
        _assets = next;
        _nextPage = response.nextPage;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || _selectedPlace?.id != place.id) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = error is AppException
            ? error.message
            : 'We could not load this place right now.';
      });
    }
  }

  Future<SlideshowPage> _fetchMoreForSlideshow(PlaceSummary place) async {
    final page = _nextPage;
    if (page == null || page.isEmpty || _isLoading) {
      return const SlideshowPage(items: [], hasMore: false);
    }
    final existingIds = _assets.map((asset) => asset.id).toSet();
    final loadPage = _loadPlace(place: place, page: page, replace: false);
    final startCount = _assets.length;
    await loadPage;
    if (!mounted || _selectedPlace?.id != place.id) {
      return const SlideshowPage(items: [], hasMore: false);
    }
    final fresh = _assets
        .skip(startCount)
        .where((asset) => !existingIds.contains(asset.id))
        .toList();
    return SlideshowPage(items: fresh, hasMore: _nextPage?.isNotEmpty ?? false);
  }
}

class _PlaceRail extends StatelessWidget {
  const _PlaceRail({
    required this.session,
    required this.places,
    required this.selectedPlace,
    required this.onPlaceSelected,
    required this.primaryContentFocusNode,
    required this.selectedPlaceFocusNode,
    required this.onOpenDrawer,
  });

  final AuthenticatedSession session;
  final List<PlaceSummary> places;
  final PlaceSummary selectedPlace;
  final ValueChanged<PlaceSummary> onPlaceSelected;
  final FocusNode primaryContentFocusNode;
  final FocusNode selectedPlaceFocusNode;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    return ListView.separated(
      key: const PageStorageKey<String>('place-rail'),
      itemCount: places.length,
      separatorBuilder: (_, _) => SizedBox(
        height: scale.space(AppSpacing.sm, min: 10, max: 12),
      ),
      itemBuilder: (context, index) {
        final place = places[index];
        final isSelected = place.id == selectedPlace.id;
        return _PlaceSummaryTile(
          session: session,
          place: place,
          isSelected: isSelected,
          focusNode: isSelected
              ? selectedPlaceFocusNode
              : (index == 0 ? primaryContentFocusNode : null),
          onOpenDrawer: onOpenDrawer,
          onPressed: () => onPlaceSelected(place),
        );
      },
    );
  }
}

class _PlaceSummaryTile extends StatelessWidget {
  const _PlaceSummaryTile({
    required this.session,
    required this.place,
    required this.isSelected,
    required this.onPressed,
    this.focusNode,
    this.onOpenDrawer,
  });

  final AuthenticatedSession session;
  final PlaceSummary place;
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
            scale.space(AppSpacing.sm, min: 10, max: 12),
          ),
          decoration: AppFocusDecoration.surface(
            isFocused: focusState.isFocused,
            isActive: isActive,
            isSelected: isSelected,
            backgroundColor: const Color(0xFF0D1A21),
            activeBackgroundColor: const Color(0xFF13212A),
            borderRadius: BorderRadius.circular(
              scale.radius(AppRadii.lg, min: 16, max: 20),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  scale.radius(AppRadii.md, min: 8, max: 12),
                ),
                child: SizedBox(
                  width: scale.sizeOf(64, min: 56, max: 72),
                  height: scale.sizeOf(64, min: 56, max: 72),
                  child: AuthenticatedAssetImage(
                    imageUrls: place.preview.thumbnailUrls,
                    accessToken: session.accessToken,
                    authMethod: session.authMethod,
                    requiresAuth: place.preview.requiresAuth,
                    placeholderIcon: Icons.place_outlined,
                    filterQuality: FilterQuality.none,
                  ),
                ),
              ),
              SizedBox(width: scale.space(AppSpacing.sm, min: 8, max: 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: scale.text(14, min: 12, max: 15),
                      ),
                    ),
                    if (place.subtitle.isNotEmpty)
                      Text(
                        place.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                          fontSize: scale.text(11, min: 10, max: 12),
                        ),
                      ),
                  ],
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
