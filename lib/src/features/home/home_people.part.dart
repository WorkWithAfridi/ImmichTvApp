part of 'home_screen.dart';

class _PeopleSectionView extends StatefulWidget {
  const _PeopleSectionView({
    required this.session,
    required this.status,
    required this.errorMessage,
    required this.people,
    required this.isSidebarOpen,
    required this.menuToggleFocusNode,
    required this.primaryContentFocusNode,
    required this.onToggleSidebar,
    required this.onOpenSidebar,
  });

  final AuthenticatedSession session;
  final LibraryLoadStatus status;
  final String? errorMessage;
  final List<PersonSummary> people;
  final bool isSidebarOpen;
  final FocusNode menuToggleFocusNode;
  final FocusNode primaryContentFocusNode;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenSidebar;

  @override
  State<_PeopleSectionView> createState() => _PeopleSectionViewState();
}

class _PeopleSectionViewState extends State<_PeopleSectionView> {
  AssetSortOrder _sortOrder = AssetSortOrder.newestFirst;

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      title: 'People',
      isSidebarOpen: widget.isSidebarOpen,
      menuToggleFocusNode: widget.menuToggleFocusNode,
      onToggleSidebar: widget.onToggleSidebar,
      trailing: _AssetSortSelector(
        value: _sortOrder,
        onChanged: (value) => setState(() => _sortOrder = value),
      ),
      child: _PeopleBrowser(
        session: widget.session,
        status: widget.status,
        errorMessage: widget.errorMessage,
        people: widget.people,
        primaryContentFocusNode: widget.primaryContentFocusNode,
        onOpenSidebar: widget.onOpenSidebar,
        sortOrder: _sortOrder,
      ),
    );
  }
}

class _PeopleBrowser extends StatefulWidget {
  const _PeopleBrowser({
    required this.session,
    required this.status,
    required this.errorMessage,
    required this.people,
    required this.primaryContentFocusNode,
    required this.onOpenSidebar,
    required this.sortOrder,
  });

  final AuthenticatedSession session;
  final LibraryLoadStatus status;
  final String? errorMessage;
  final List<PersonSummary> people;
  final FocusNode primaryContentFocusNode;
  final VoidCallback onOpenSidebar;
  final AssetSortOrder sortOrder;

  @override
  State<_PeopleBrowser> createState() => _PeopleBrowserState();
}

class _PeopleBrowserState extends State<_PeopleBrowser> {
  static const _personRefreshInterval = Duration(minutes: 1);

  final FocusNode _selectedPersonFocusNode = FocusNode(
    debugLabel: 'people.selected-person',
  );
  PersonSummary? _selectedPerson;
  List<AssetSummary> _personAssets = const [];
  String? _personAssetsNextPage;
  bool _isLoadingPersonAssets = false;
  String? _personAssetsError;
  Timer? _personRefreshTimer;

  @override
  void dispose() {
    _personRefreshTimer?.cancel();
    _selectedPersonFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PeopleBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.people.isEmpty) {
      _selectedPerson = null;
      _personAssets = const [];
      _personAssetsNextPage = null;
      _personAssetsError = null;
      _isLoadingPersonAssets = false;
      return;
    }

    final selectedPersonStillExists =
        _selectedPerson != null &&
        widget.people.any((person) => person.id == _selectedPerson!.id);
    if (!selectedPersonStillExists) {
      _selectPerson(widget.people.first);
      return;
    }

    if (_selectedPerson != null) {
      final refreshedSelectedPerson = widget.people.firstWhere(
        (person) => person.id == _selectedPerson!.id,
      );
      if (refreshedSelectedPerson != _selectedPerson) {
        _selectedPerson = refreshedSelectedPerson;
      }
    }

    if (oldWidget.sortOrder != widget.sortOrder && _selectedPerson != null) {
      _selectPerson(_selectedPerson!);
    }
  }

  @override
  Widget build(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (widget.status == LibraryLoadStatus.loading) {
      return const _AlbumBrowserLoadingSkeleton();
    }

    if (widget.status == LibraryLoadStatus.failure) {
      return _InfoPanel(
        title: 'People are unavailable right now',
        body: widget.errorMessage ?? 'Try again in a moment.',
        accent: AppColors.error,
      );
    }

    if (widget.people.isEmpty) {
      return const _InfoPanel(
        title: 'No people yet',
        body: 'Recognized faces will appear here.',
        accent: AppColors.textMuted,
      );
    }

    final selectedPerson = _selectedPerson ?? widget.people.first;

    if (_selectedPerson == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectPerson(widget.people.first);
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = AppScale.of(context);
        final peopleRail = _PeopleRail(
          session: widget.session,
          people: widget.people,
          selectedPerson: selectedPerson,
          onPersonSelected: _selectPerson,
          primaryContentFocusNode: widget.primaryContentFocusNode,
          selectedPersonFocusNode: _selectedPersonFocusNode,
          onOpenDrawer: widget.onOpenSidebar,
        );

        return Row(
          children: [
            SizedBox(
              width: _responsiveAlbumRailWidth(constraints.maxWidth, scale),
              child: peopleRail,
            ),
            SizedBox(width: scale.space(AppSpacing.xl, min: 24, max: 32)),
            Expanded(child: _buildPersonContent(selectedPerson)),
          ],
        );
      },
    );
  }

  void _selectPerson(PersonSummary person) {
    _ensurePersonRefreshPolling();
    setState(() {
      _selectedPerson = person;
      _personAssets = const [];
      _personAssetsNextPage = null;
      _personAssetsError = null;
      _isLoadingPersonAssets = false;
    });
    _loadPersonAssets(person: person, page: null, replace: true);
  }

  Widget _buildPersonContent(PersonSummary selectedPerson) {
    if (_isLoadingPersonAssets && _personAssets.isEmpty) {
      return const _AssetGridLoadingSkeleton(
        leadingHeight: 20,
        leadingWidth: 220,
      );
    }

    if (_personAssetsError != null && _personAssets.isEmpty) {
      return _InfoPanel(
        title: 'This person could not load',
        body: _personAssetsError!,
        accent: AppColors.error,
      );
    }

    if (_personAssets.isEmpty) {
      return _InfoPanel(
        title: 'No assets for ${selectedPerson.name}',
        body:
            'This person does not have any recognized assets that can be displayed yet.',
        accent: AppColors.textMuted,
      );
    }

    return _GroupedAssetSectionList(
      session: widget.session,
      assets: _personAssets,
      hasMore:
          _personAssetsNextPage != null && _personAssetsNextPage!.isNotEmpty,
      isLoadingMore: _isLoadingPersonAssets && _personAssets.isNotEmpty,
      storageKey: 'person-list-${selectedPerson.id}',
      onLoadMore: _loadMorePersonAssets,
      onOpenSidebar: widget.onOpenSidebar,
      onMoveLeftFromGrid: () => _selectedPersonFocusNode.requestFocus(),
      slideshowPageLoader: _fetchMoreForSlideshow,
      hasMoreSlideshowPages: _personAssetsNextPage?.isNotEmpty ?? false,
      headingTitle: selectedPerson.name,
      headingSubtitle: '${_personAssets.length} assets',
    );
  }

  Future<SlideshowPage> _fetchMoreForSlideshow() async {
    final person = _selectedPerson;
    final page = _personAssetsNextPage;
    if (person == null ||
        page == null ||
        page.isEmpty ||
        _isLoadingPersonAssets) {
      return const SlideshowPage(items: [], hasMore: false);
    }

    try {
      final response = await context.read<MediaRepository>().fetchPersonAssetsPage(
        widget.session,
        personId: person.id,
        sortOrder: widget.sortOrder,
        page: page,
      );
      final existingIds = _personAssets.map((asset) => asset.id).toSet();
      final fresh = response.items
          .where((asset) => !existingIds.contains(asset.id))
          .toList();
      if (!mounted || _selectedPerson?.id != person.id) {
        return const SlideshowPage(items: [], hasMore: false);
      }
      setState(() {
        _personAssets = [..._personAssets, ...fresh];
        _personAssetsNextPage = response.nextPage;
      });
      return SlideshowPage(items: fresh, hasMore: response.hasMore);
    } catch (_) {
      return const SlideshowPage(items: [], hasMore: false);
    }
  }

  Future<void> _loadMorePersonAssets() async {
    final selectedPerson = _selectedPerson;
    final nextPage = _personAssetsNextPage;
    if (selectedPerson == null || nextPage == null || _isLoadingPersonAssets) {
      return;
    }

    await _loadPersonAssets(
      person: selectedPerson,
      page: nextPage,
      replace: false,
    );
  }

  Future<void> _loadPersonAssets({
    required PersonSummary person,
    required String? page,
    required bool replace,
    bool background = false,
  }) async {
    if (_isLoadingPersonAssets) {
      return;
    }

    if (background) {
      _ensurePersonRefreshPolling();
    } else {
      setState(() {
        _isLoadingPersonAssets = true;
        _personAssetsError = null;
      });
    }

    try {
      final response = await context
          .read<MediaRepository>()
          .fetchPersonAssetsPage(
            widget.session,
            personId: person.id,
            sortOrder: widget.sortOrder,
            page: page,
          );
      if (!mounted || _selectedPerson?.id != person.id) {
        return;
      }

      final nextAssets = replace
          ? _mergeRefreshedPeopleAssets(
              existing: _personAssets,
              refreshedFirstPage: response.items,
            )
          : [
              ..._personAssets,
              ..._dedupePeopleAssets(_personAssets, response.items),
            ];
      final hasChanges =
          !_listEquals(_personAssets, nextAssets) ||
          _personAssetsNextPage != response.nextPage ||
          _isLoadingPersonAssets;
      if (!hasChanges && background) {
        return;
      }

      setState(() {
        _personAssets = nextAssets;
        _personAssetsNextPage = response.nextPage;
        _isLoadingPersonAssets = false;
        if (!background) {
          _personAssetsError = null;
        }
      });
    } catch (error) {
      if (!mounted || _selectedPerson?.id != person.id) {
        return;
      }

      if (background) {
        return;
      }

      setState(() {
        _isLoadingPersonAssets = false;
        _personAssetsError = error is AppException
            ? error.message
            : 'We could not load this person right now.';
      });
    }
  }

  List<AssetSummary> _dedupePeopleAssets(
    List<AssetSummary> existing,
    List<AssetSummary> incoming,
  ) {
    final existingIds = existing.map((item) => item.id).toSet();
    return incoming
        .where((item) => !existingIds.contains(item.id))
        .toList(growable: false);
  }

  List<AssetSummary> _mergeRefreshedPeopleAssets({
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

  void _ensurePersonRefreshPolling() {
    _personRefreshTimer ??= Timer.periodic(_personRefreshInterval, (_) {
      final selectedPerson = _selectedPerson;
      if (!mounted ||
          selectedPerson == null ||
          widget.status != LibraryLoadStatus.success) {
        return;
      }
      unawaited(
        _loadPersonAssets(
          person: selectedPerson,
          page: null,
          replace: true,
          background: true,
        ),
      );
    });
  }
}

class _PeopleRail extends StatelessWidget {
  const _PeopleRail({
    required this.session,
    required this.people,
    required this.selectedPerson,
    required this.onPersonSelected,
    required this.primaryContentFocusNode,
    required this.selectedPersonFocusNode,
    required this.onOpenDrawer,
  });

  final AuthenticatedSession session;
  final List<PersonSummary> people;
  final PersonSummary selectedPerson;
  final ValueChanged<PersonSummary> onPersonSelected;
  final FocusNode primaryContentFocusNode;
  final FocusNode selectedPersonFocusNode;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    return ListView.separated(
      key: const PageStorageKey<String>('people-rail-vertical'),
      itemCount: people.length,
      separatorBuilder: (_, _) =>
          SizedBox(height: scale.space(AppSpacing.sm, min: 10, max: 12)),
      itemBuilder: (context, index) {
        final person = people[index];
        return _PersonSummaryTile(
          session: session,
          person: person,
          isSelected: person.id == selectedPerson.id,
          focusNode: person.id == selectedPerson.id
              ? selectedPersonFocusNode
              : (index == 0 ? primaryContentFocusNode : null),
          onOpenDrawer: onOpenDrawer,
          onPressed: () => onPersonSelected(person),
        );
      },
    );
  }
}

class _PersonSummaryTile extends StatefulWidget {
  const _PersonSummaryTile({
    required this.session,
    required this.person,
    required this.isSelected,
    this.focusNode,
    this.onOpenDrawer,
    required this.onPressed,
  });

  final AuthenticatedSession session;
  final PersonSummary person;
  final bool isSelected;
  final FocusNode? focusNode;
  final VoidCallback? onOpenDrawer;
  final VoidCallback onPressed;

  @override
  State<_PersonSummaryTile> createState() => _PersonSummaryTileState();
}

class _PersonSummaryTileState extends State<_PersonSummaryTile> {
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
            scale.space(AppSpacing.md, min: 14, max: 18),
          ),
          decoration: AppFocusDecoration.surface(
            isFocused: isFocused,
            isActive: isActive,
            isSelected: widget.isSelected,
            backgroundColor: const Color(0xFF0D1A21),
            activeBackgroundColor: const Color(0xFF13212A),
            borderRadius: BorderRadius.circular(
              scale.radius(AppRadii.lg, min: 20, max: 24),
            ),
          ),
          child: Row(
            children: [
              _PersonAvatar(session: widget.session, person: widget.person),
              SizedBox(width: scale.space(AppSpacing.md, min: 14, max: 16)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.person.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: scale.text(14, min: 12, max: 14),
                        height: 1.2,
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

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.session, required this.person});

  final AuthenticatedSession session;
  final PersonSummary person;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    final size = scale.sizeOf(56, min: 48, max: 60);
    final primaryUrl = person.thumbnailUrls.isNotEmpty
        ? person.thumbnailUrls.first
        : null;

    if (primaryUrl != null && primaryUrl.startsWith('mock://')) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceMuted,
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Center(
          child: Text(
            person.name.characters.first.toUpperCase(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontSize: scale.text(20, min: 16, max: 22),
            ),
          ),
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: AuthenticatedAssetImage(
          imageUrls: person.thumbnailUrls,
          accessToken: session.accessToken,
          authMethod: session.authMethod,
          requiresAuth: true,
          fit: BoxFit.cover,
          placeholderIcon: Icons.person_outline_rounded,
        ),
      ),
    );
  }
}
