part of 'home_screen.dart';

/// TV-first "On this day" gallery. Each card opens the existing fullscreen
/// viewer with that memory's assets so slideshow and transport controls keep
/// working exactly as they do in the timeline.
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
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (status == LibraryLoadStatus.loading) {
      return const _AssetGridLoadingSkeleton();
    }

    if (status == LibraryLoadStatus.failure) {
      return _InfoPanel(
        title: 'Memories could not load',
        body: errorMessage ?? 'Try again in a moment.',
        accent: AppColors.error,
      );
    }

    if (memories.isEmpty) {
      return const _InfoPanel(
        title: 'No memories yet',
        body: 'Memories appear here as you collect photos on this day in past years. They also require the Memories feature to be enabled on your Immich server.',
        accent: AppColors.textMuted,
      );
    }

    return ListView.builder(
      key: const PageStorageKey<String>('memories-list'),
      cacheExtent: 480,
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final memory = memories[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == memories.length - 1 ? 0 : AppSpacing.xl,
          ),
          child: _MemoryCard(
            session: session,
            memory: memory,
            focusNode: index == 0 ? primaryContentFocusNode : null,
            autofocus: index == 0,
            onOpenSidebar: onOpenSidebar,
          ),
        );
      },
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.session,
    required this.memory,
    required this.onOpenSidebar,
    this.focusNode,
    this.autofocus = false,
  });

  final AuthenticatedSession session;
  final MemorySummary memory;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback onOpenSidebar;

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    final theme = Theme.of(context);
    final previewAssets = memory.assets.take(5).toList(growable: false);

    final card = TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: () => AssetViewerScreen.show(
        context,
        assets: memory.assets,
        initialIndex: 0,
        accessToken: session.accessToken,
        authMethod: session.authMethod,
      ),
      builder: (context, focusState) {
        return AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: focusState.isActive ? 0.995 : 1,
          child: DecoratedBox(
            decoration: AppFocusDecoration.surface(
              isFocused: focusState.isFocused,
              isActive: focusState.isActive,
              backgroundColor: const Color(0xFF0D1A21),
              activeBackgroundColor: const Color(0xFF111F26),
              borderRadius: BorderRadius.circular(
                scale.radius(AppRadii.lg, min: 14, max: 18),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(scale.space(AppSpacing.md, min: 14, max: 18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        memory.isBirthday
                            ? Icons.cake_outlined
                            : Icons.auto_awesome_outlined,
                        color: AppColors.warning,
                        size: scale.sizeOf(20, min: 18, max: 22),
                      ),
                      SizedBox(width: scale.space(AppSpacing.sm, min: 8, max: 10)),
                      Expanded(
                        child: Text(
                          memory.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: scale.text(19, min: 16, max: 20),
                          ),
                        ),
                      ),
                      Text(
                        memory.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                          fontSize: scale.text(12, min: 11, max: 13),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: scale.space(AppSpacing.md, min: 12, max: 16)),
                  SizedBox(
                    height: scale.sizeOf(150, min: 108, max: 180),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        scale.radius(AppRadii.md, min: 10, max: 14),
                      ),
                      child: Row(
                        children: [
                          for (final asset in previewAssets)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: asset == previewAssets.last ? 0 : 3,
                                ),
                                child: AuthenticatedAssetImage(
                                  imageUrls: asset.thumbnailUrls,
                                  accessToken: session.accessToken,
                                  authMethod: session.authMethod,
                                  requiresAuth: asset.requiresAuth,
                                  placeholderIcon: asset.isVideo
                                      ? Icons.smart_display_outlined
                                      : Icons.photo_outlined,
                                  filterQuality: FilterQuality.none,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: scale.space(AppSpacing.sm, min: 8, max: 10)),
                  Text(
                    '${memory.assets.length} ${memory.assets.length == 1 ? 'photo' : 'photos'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: scale.text(12, min: 11, max: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (focusNode == null) {
      return card;
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _OpenDrawerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenDrawerIntent: CallbackAction<_OpenDrawerIntent>(
            onInvoke: (_) {
              onOpenSidebar();
              return null;
            },
          ),
        },
        child: card,
      ),
    );
  }
}
