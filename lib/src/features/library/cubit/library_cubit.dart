import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/models/asset_sort_order.dart';
import '../../../core/models/asset_summary.dart';
import '../../../core/models/authenticated_session.dart';
import '../../../core/models/media_page.dart';
import '../../../core/network/network_failure.dart';
import '../../../core/repositories/media_repository.dart';
import '../../slideshow/slideshow_page_loader.dart';
import 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit(
    this._mediaRepository,
    this._session, {
    Duration refreshInterval = const Duration(minutes: 1),
  }) : _refreshInterval = refreshInterval,
       super(LibraryState(selectedTimelineYear: DateTime.now().year));

  final MediaRepository _mediaRepository;
  final AuthenticatedSession _session;
  final Duration _refreshInterval;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  Future<void> loadInitial() async {
    emit(state.copyWith(status: LibraryLoadStatus.loading, clearError: true));

    try {
      final timeline = await _mediaRepository.fetchTimelinePage(
        _session,
        year: state.selectedTimelineYear,
      );

      _emitLoaded(
        state.copyWith(
          status: LibraryLoadStatus.success,
          timeline: timeline.items,
          timelineNextPage: timeline.nextPage,
          clearTimelineNextPage: timeline.nextPage == null,
          hasLoadedTimeline: true,
          isLoadingMore: false,
          clearError: true,
        ),
      );
      _ensureRefreshPolling();
      unawaited(_preloadInitialSupportingSections());
    } catch (error) {
      _emitFailure(
        state.copyWith(
          status: LibraryLoadStatus.failure,
          errorMessage: error is AppException
              ? error.message
              : 'We could not load your library right now.',
        ),
        error,
      );
    }
  }

  LibraryState _loaded(LibraryState next) {
    return next.copyWith(lastUpdatedAt: DateTime.now(), isOffline: false);
  }

  void _emitLoaded(LibraryState next) {
    if (isClosed) {
      return;
    }
    emit(_loaded(next));
  }

  void _emitFailure(LibraryState next, Object error) {
    if (isClosed) {
      return;
    }
    emit(
      next.copyWith(
        isOffline: next.isOffline || NetworkFailure.isConnectivityIssue(error),
      ),
    );
  }

  Future<void> _preloadInitialSupportingSections() async {
    Object? connectivityFailure;

    Future<T?> safely<T>(Future<T> Function() fetch) async {
      try {
        return await fetch();
      } catch (error) {
        if (NetworkFailure.isConnectivityIssue(error)) {
          connectivityFailure ??= error;
        }
        return null;
      }
    }

    final nextAlbums = await safely(() => _mediaRepository.fetchAlbums(_session));
    final nextFavorites = await safely(
      () => _mediaRepository.fetchFavoritesPage(
        _session,
        sortOrder: state.favoritesSortOrder,
      ),
    );
    final nextPeople = await safely(() => _mediaRepository.fetchPeople(_session));
    final nextMemories = await safely(
      () => _mediaRepository.fetchMemories(_session),
    );
    final nextPlaces = await safely(() => _mediaRepository.fetchPlaces(_session));

    if (isClosed) {
      return;
    }

    final nextState = state.copyWith(
      albums: nextAlbums ?? state.albums,
      hasLoadedAlbums: nextAlbums != null || state.hasLoadedAlbums,
      favorites: nextFavorites?.items ?? state.favorites,
      favoritesNextPage: nextFavorites?.nextPage,
      clearFavoritesNextPage:
          nextFavorites != null && nextFavorites.nextPage == null,
      hasLoadedFavorites: nextFavorites != null || state.hasLoadedFavorites,
      people: nextPeople ?? state.people,
      hasLoadedPeople: nextPeople != null || state.hasLoadedPeople,
      memories: nextMemories ?? state.memories,
      hasLoadedMemories: nextMemories != null || state.hasLoadedMemories,
      places: nextPlaces ?? state.places,
      hasLoadedPlaces: nextPlaces != null || state.hasLoadedPlaces,
      isOffline: connectivityFailure != null,
    );

    if (nextState != state) {
      emit(nextState);
    }
  }

  Future<void> selectTab(LibraryTab tab) async {
    if (_isTabLoaded(tab)) {
      emit(
        state.copyWith(
          selectedTab: tab,
          status: LibraryLoadStatus.success,
          clearError: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        selectedTab: tab,
        status: LibraryLoadStatus.loading,
        clearError: true,
      ),
    );

    try {
      switch (tab) {
        case LibraryTab.timeline:
          final timeline = await _mediaRepository.fetchTimelinePage(
            _session,
            year: state.selectedTimelineYear,
          );
          _emitLoaded(
            state.copyWith(
              selectedTab: tab,
              timeline: timeline.items,
              timelineNextPage: timeline.nextPage,
              clearTimelineNextPage: timeline.nextPage == null,
              hasLoadedTimeline: true,
              status: LibraryLoadStatus.success,
              isLoadingMore: false,
              clearError: true,
            ),
          );
          _ensureRefreshPolling();
        case LibraryTab.albums:
          final albums = await _mediaRepository.fetchAlbums(_session);
          _emitLoaded(
            state.copyWith(
              selectedTab: tab,
              albums: albums,
              hasLoadedAlbums: true,
              status: LibraryLoadStatus.success,
              isLoadingMore: false,
              clearError: true,
            ),
          );
          _ensureRefreshPolling();
        case LibraryTab.people:
          final people = await _mediaRepository.fetchPeople(_session);
          _emitLoaded(
            state.copyWith(
              selectedTab: tab,
              people: people,
              hasLoadedPeople: true,
              status: LibraryLoadStatus.success,
              isLoadingMore: false,
              clearError: true,
            ),
          );
          _ensureRefreshPolling();
        case LibraryTab.favorites:
          final favorites = await _mediaRepository.fetchFavoritesPage(
            _session,
            sortOrder: state.favoritesSortOrder,
          );
          _emitLoaded(
            state.copyWith(
              selectedTab: tab,
              favorites: favorites.items,
              favoritesNextPage: favorites.nextPage,
              clearFavoritesNextPage: favorites.nextPage == null,
              hasLoadedFavorites: true,
              status: LibraryLoadStatus.success,
              isLoadingMore: false,
              clearError: true,
            ),
          );
          _ensureRefreshPolling();
        case LibraryTab.memories:
          final memories = await _mediaRepository.fetchMemories(_session);
          _emitLoaded(
            state.copyWith(
              selectedTab: tab,
              memories: memories,
              hasLoadedMemories: true,
              status: LibraryLoadStatus.success,
              isLoadingMore: false,
              clearError: true,
            ),
          );
          _ensureRefreshPolling();
        case LibraryTab.places:
          final places = await _mediaRepository.fetchPlaces(_session);
          _emitLoaded(
            state.copyWith(
              selectedTab: tab,
              places: places,
              hasLoadedPlaces: true,
              status: LibraryLoadStatus.success,
              isLoadingMore: false,
              clearError: true,
            ),
          );
          _ensureRefreshPolling();
        case LibraryTab.settings:
          // Settings is rendered from its own cubit and loads no library data.
          emit(
            state.copyWith(
              selectedTab: tab,
              status: LibraryLoadStatus.success,
              isLoadingMore: false,
              clearError: true,
            ),
          );
      }
    } catch (error) {
      _emitFailure(
        state.copyWith(
          selectedTab: tab,
          status: LibraryLoadStatus.failure,
          errorMessage: error is AppException
              ? error.message
              : 'We could not load this section right now.',
        ),
        error,
      );
    }
  }

  /// Fetches the next page for a running slideshow and returns only the new
  /// assets. The library state is updated as well so returning to the grid
  /// shows the same assets the slideshow just played.
  Future<SlideshowPage> fetchMoreForSlideshow() async {
    try {
      switch (state.selectedTab) {
        case LibraryTab.timeline:
          final page = state.timelineNextPage;
          if (page == null || page.isEmpty) break;
          final response = await _mediaRepository.fetchTimelinePage(
            _session,
            page: page,
            year: state.selectedTimelineYear,
          );
          final fresh = _dedupeAssets(state.timeline, response).cast<AssetSummary>();
          _emitLoaded(
            state.copyWith(
              timeline: [...state.timeline, ...fresh],
              timelineNextPage: response.nextPage,
              clearTimelineNextPage: response.nextPage == null,
            ),
          );
          return SlideshowPage(items: fresh, hasMore: response.hasMore);
        case LibraryTab.favorites:
          final page = state.favoritesNextPage;
          if (page == null || page.isEmpty) break;
          final response = await _mediaRepository.fetchFavoritesPage(
            _session,
            page: page,
            sortOrder: state.favoritesSortOrder,
          );
          final fresh = _dedupeAssets(state.favorites, response).cast<AssetSummary>();
          _emitLoaded(
            state.copyWith(
              favorites: [...state.favorites, ...fresh],
              favoritesNextPage: response.nextPage,
              clearFavoritesNextPage: response.nextPage == null,
            ),
          );
          return SlideshowPage(items: fresh, hasMore: response.hasMore);
        default:
          break;
      }
    } catch (_) {
      // The slideshow falls back to wrapping when paging is unavailable.
    }
    return const SlideshowPage(items: [], hasMore: false);
  }

  Future<void> loadMore() async {
    if (state.status != LibraryLoadStatus.success || state.isLoadingMore) {
      return;
    }

    switch (state.selectedTab) {
      case LibraryTab.timeline:
        if (!state.hasMoreTimeline) {
          return;
        }
        await _appendTimelinePage(state.timelineNextPage!);
      case LibraryTab.favorites:
        if (!state.hasMoreFavorites) {
          return;
        }
        await _appendFavoritesPage(state.favoritesNextPage!);
      case LibraryTab.people:
        return;
      case LibraryTab.albums:
        return;
      case LibraryTab.memories:
        return;
      case LibraryTab.places:
        return;
      case LibraryTab.settings:
        return;
    }
  }

  Future<void> selectTimelineYear(int year) async {
    if (state.selectedTimelineYear == year &&
        state.selectedTab == LibraryTab.timeline &&
        state.hasLoadedTimeline) {
      return;
    }

    emit(
      state.copyWith(
        selectedTimelineYear: year,
        selectedTab: LibraryTab.timeline,
        status: LibraryLoadStatus.loading,
        clearError: true,
      ),
    );

    try {
      final timeline = await _mediaRepository.fetchTimelinePage(
        _session,
        year: year,
      );
      _emitLoaded(
        state.copyWith(
          selectedTimelineYear: year,
          selectedTab: LibraryTab.timeline,
          timeline: timeline.items,
          timelineNextPage: timeline.nextPage,
          clearTimelineNextPage: timeline.nextPage == null,
          hasLoadedTimeline: true,
          status: LibraryLoadStatus.success,
          isLoadingMore: false,
          clearError: true,
        ),
      );
      _ensureRefreshPolling();
    } catch (error) {
      _emitFailure(
        state.copyWith(
          selectedTimelineYear: year,
          selectedTab: LibraryTab.timeline,
          status: LibraryLoadStatus.failure,
          errorMessage: error is AppException
              ? error.message
              : 'We could not load this year right now.',
        ),
        error,
      );
    }
  }

  Future<void> updateFavoritesSortOrder(AssetSortOrder sortOrder) async {
    if (state.favoritesSortOrder == sortOrder) {
      return;
    }

    emit(
      state.copyWith(
        favoritesSortOrder: sortOrder,
        selectedTab: LibraryTab.favorites,
        status: LibraryLoadStatus.loading,
        favorites: const [],
        clearFavoritesNextPage: true,
        hasLoadedFavorites: false,
        clearError: true,
      ),
    );

    try {
      final favorites = await _mediaRepository.fetchFavoritesPage(
        _session,
        sortOrder: sortOrder,
      );
      _emitLoaded(
        state.copyWith(
          favoritesSortOrder: sortOrder,
          selectedTab: LibraryTab.favorites,
          favorites: favorites.items,
          favoritesNextPage: favorites.nextPage,
          clearFavoritesNextPage: favorites.nextPage == null,
          hasLoadedFavorites: true,
          status: LibraryLoadStatus.success,
          isLoadingMore: false,
          clearError: true,
        ),
      );
      _ensureRefreshPolling();
    } catch (error) {
      _emitFailure(
        state.copyWith(
          favoritesSortOrder: sortOrder,
          selectedTab: LibraryTab.favorites,
          status: LibraryLoadStatus.failure,
          errorMessage: error is AppException
              ? error.message
              : 'We could not load this section right now.',
        ),
        error,
      );
    }
  }

  Future<void> _appendTimelinePage(String page) async {
    emit(state.copyWith(isLoadingMore: true, clearError: true));

    try {
      final response = await _mediaRepository.fetchTimelinePage(
        _session,
        page: page,
        year: state.selectedTimelineYear,
      );
      emit(
        state.copyWith(
          timeline: [
            ...state.timeline,
            ..._dedupeAssets(state.timeline, response),
          ],
          timelineNextPage: response.nextPage,
          clearTimelineNextPage: response.nextPage == null,
          isLoadingMore: false,
          clearError: true,
        ),
      );
    } catch (error) {
      _emitFailure(
        state.copyWith(
          isLoadingMore: false,
          errorMessage: error is AppException
              ? error.message
              : 'We could not load more timeline photos right now.',
        ),
        error,
      );
    }
  }

  Future<void> _appendFavoritesPage(String page) async {
    emit(state.copyWith(isLoadingMore: true, clearError: true));

    try {
      final response = await _mediaRepository.fetchFavoritesPage(
        _session,
        page: page,
        sortOrder: state.favoritesSortOrder,
      );
      emit(
        state.copyWith(
          favorites: [
            ...state.favorites,
            ..._dedupeAssets(state.favorites, response),
          ],
          favoritesNextPage: response.nextPage,
          clearFavoritesNextPage: response.nextPage == null,
          isLoadingMore: false,
          clearError: true,
        ),
      );
    } catch (error) {
      _emitFailure(
        state.copyWith(
          isLoadingMore: false,
          errorMessage: error is AppException
              ? error.message
              : 'We could not load more favorite photos right now.',
        ),
        error,
      );
    }
  }

  List<dynamic> _dedupeAssets(
    List<dynamic> existing,
    MediaPage<dynamic> response,
  ) {
    final existingIds = existing.map((item) => item.id as String).toSet();
    return response.items
        .where((item) => !existingIds.contains(item.id))
        .toList(growable: false);
  }

  bool _isTabLoaded(LibraryTab tab) {
    return switch (tab) {
      LibraryTab.timeline => state.hasLoadedTimeline,
      LibraryTab.albums => state.hasLoadedAlbums,
      LibraryTab.people => state.hasLoadedPeople,
      LibraryTab.favorites => state.hasLoadedFavorites,
      LibraryTab.memories => state.hasLoadedMemories,
      LibraryTab.places => state.hasLoadedPlaces,
      LibraryTab.settings => true,
    };
  }

  void _ensureRefreshPolling() {
    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
      unawaited(refreshContent());
    });
  }

  /// Manual retry entry point used by the offline banner.
  Future<void> retry() => refreshContent(force: true);

  Future<void> refreshContent({bool force = false}) async {
    if (_isRefreshing || state.isLoadingMore) {
      return;
    }
    if (!force && state.status != LibraryLoadStatus.success) {
      return;
    }

    _isRefreshing = true;
    try {
      final timelineFuture = _mediaRepository.fetchTimelinePage(
        _session,
        year: state.selectedTimelineYear,
      );
      final favoritesFuture = _mediaRepository.fetchFavoritesPage(
        _session,
        sortOrder: state.favoritesSortOrder,
      );
      final albumsFuture = _mediaRepository.fetchAlbums(_session);
      final memoriesFuture = _mediaRepository.fetchMemories(_session);
      final placesFuture = _mediaRepository.fetchPlaces(_session);
      final timeline = await timelineFuture;
      final favorites = await favoritesFuture;
      final albums = await albumsFuture;
      final memories = await memoriesFuture;
      final places = await placesFuture;

      final refreshedTimeline = _mergeRefreshedAssets(
        existing: state.timeline,
        refreshedFirstPage: timeline.items,
      );
      final refreshedFavorites = _mergeRefreshedAssets(
        existing: state.favorites,
        refreshedFirstPage: favorites.items,
      );

      final nextState = state.copyWith(
        timeline: refreshedTimeline,
        timelineNextPage: timeline.nextPage,
        clearTimelineNextPage: timeline.nextPage == null,
        favorites: refreshedFavorites,
        favoritesNextPage: favorites.nextPage,
        clearFavoritesNextPage: favorites.nextPage == null,
        albums: albums,
        memories: memories,
        places: places,
        hasLoadedTimeline: true,
        hasLoadedFavorites: true,
        hasLoadedAlbums: true,
        hasLoadedMemories: true,
        hasLoadedPlaces: true,
        status: LibraryLoadStatus.success,
        isOffline: false,
        clearError: true,
      );

      if (nextState != state) {
        emit(nextState.copyWith(lastUpdatedAt: DateTime.now()));
      }
    } catch (error) {
      // Keep the current surface stable on background refresh failures, but
      // let the UI know that the data on screen may be stale.
      _emitFailure(state, error);
    } finally {
      _isRefreshing = false;
    }
  }

  List<AssetSummary> _mergeRefreshedAssets({
    required List<AssetSummary> existing,
    required List<AssetSummary> refreshedFirstPage,
  }) {
    if (existing.isEmpty) {
      return refreshedFirstPage;
    }

    if (listEquals(existing, refreshedFirstPage)) {
      return existing;
    }

    final refreshedIds = refreshedFirstPage.map((item) => item.id).toSet();
    final trailingItems = existing
        .where((item) => !refreshedIds.contains(item.id))
        .toList(growable: false);
    return List<AssetSummary>.unmodifiable([
      ...refreshedFirstPage,
      ...trailingItems,
    ]);
  }

  @override
  Future<void> close() {
    _refreshTimer?.cancel();
    return super.close();
  }
}
