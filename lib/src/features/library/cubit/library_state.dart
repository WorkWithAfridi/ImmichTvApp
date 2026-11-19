import 'package:equatable/equatable.dart';

import '../../../core/models/album_summary.dart';
import '../../../core/models/asset_sort_order.dart';
import '../../../core/models/asset_summary.dart';
import '../../../core/models/memory_summary.dart';
import '../../../core/models/person_summary.dart';

enum LibraryTab { timeline, albums, people, favorites, memories, settings }

enum LibraryLoadStatus { idle, loading, success, failure }

class LibraryState extends Equatable {
  const LibraryState({
    this.selectedTab = LibraryTab.timeline,
    this.selectedTimelineYear = 0,
    this.favoritesSortOrder = AssetSortOrder.newestFirst,
    this.status = LibraryLoadStatus.idle,
    this.timeline = const [],
    this.albums = const [],
    this.people = const [],
    this.favorites = const [],
    this.memories = const [],
    this.hasLoadedTimeline = false,
    this.hasLoadedAlbums = false,
    this.hasLoadedPeople = false,
    this.hasLoadedFavorites = false,
    this.hasLoadedMemories = false,
    this.timelineNextPage,
    this.favoritesNextPage,
    this.isLoadingMore = false,
    this.errorMessage,
    this.isOffline = false,
    this.lastUpdatedAt,
  });

  final LibraryTab selectedTab;
  final int selectedTimelineYear;
  final AssetSortOrder favoritesSortOrder;
  final LibraryLoadStatus status;
  final List<AssetSummary> timeline;
  final List<AlbumSummary> albums;
  final List<PersonSummary> people;
  final List<AssetSummary> favorites;
  final List<MemorySummary> memories;
  final bool hasLoadedTimeline;
  final bool hasLoadedAlbums;
  final bool hasLoadedPeople;
  final bool hasLoadedFavorites;
  final bool hasLoadedMemories;
  final String? timelineNextPage;
  final String? favoritesNextPage;
  final bool isLoadingMore;
  final String? errorMessage;
  final bool isOffline;
  final DateTime? lastUpdatedAt;

  bool get isLoading => status == LibraryLoadStatus.loading;

  bool get hasMoreTimeline =>
      timelineNextPage != null && timelineNextPage!.isNotEmpty;

  bool get hasMoreFavorites =>
      favoritesNextPage != null && favoritesNextPage!.isNotEmpty;

  bool get hasMoreForSelectedTab {
    return switch (selectedTab) {
      LibraryTab.timeline => hasMoreTimeline,
      LibraryTab.people => false,
      LibraryTab.favorites => hasMoreFavorites,
      LibraryTab.memories => false,
      LibraryTab.albums => false,
      LibraryTab.settings => false,
    };
  }

  List<Object> get activeItems {
    return switch (selectedTab) {
      LibraryTab.timeline => timeline,
      LibraryTab.albums => albums,
      LibraryTab.people => people,
      LibraryTab.favorites => favorites,
      LibraryTab.memories => memories,
      LibraryTab.settings => const <Object>[],
    };
  }

  LibraryState copyWith({
    LibraryTab? selectedTab,
    int? selectedTimelineYear,
    AssetSortOrder? favoritesSortOrder,
    LibraryLoadStatus? status,
    List<AssetSummary>? timeline,
    List<AlbumSummary>? albums,
    List<PersonSummary>? people,
    List<AssetSummary>? favorites,
    List<MemorySummary>? memories,
    bool? hasLoadedTimeline,
    bool? hasLoadedAlbums,
    bool? hasLoadedPeople,
    bool? hasLoadedFavorites,
    bool? hasLoadedMemories,
    String? timelineNextPage,
    String? favoritesNextPage,
    bool? isLoadingMore,
    String? errorMessage,
    bool? isOffline,
    DateTime? lastUpdatedAt,
    bool clearError = false,
    bool clearTimelineNextPage = false,
    bool clearFavoritesNextPage = false,
  }) {
    return LibraryState(
      selectedTab: selectedTab ?? this.selectedTab,
      selectedTimelineYear: selectedTimelineYear ?? this.selectedTimelineYear,
      favoritesSortOrder: favoritesSortOrder ?? this.favoritesSortOrder,
      status: status ?? this.status,
      timeline: timeline ?? this.timeline,
      albums: albums ?? this.albums,
      people: people ?? this.people,
      favorites: favorites ?? this.favorites,
      memories: memories ?? this.memories,
      hasLoadedTimeline: hasLoadedTimeline ?? this.hasLoadedTimeline,
      hasLoadedAlbums: hasLoadedAlbums ?? this.hasLoadedAlbums,
      hasLoadedPeople: hasLoadedPeople ?? this.hasLoadedPeople,
      hasLoadedFavorites: hasLoadedFavorites ?? this.hasLoadedFavorites,
      hasLoadedMemories: hasLoadedMemories ?? this.hasLoadedMemories,
      timelineNextPage: clearTimelineNextPage
          ? null
          : (timelineNextPage ?? this.timelineNextPage),
      favoritesNextPage: clearFavoritesNextPage
          ? null
          : (favoritesNextPage ?? this.favoritesNextPage),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isOffline: isOffline ?? this.isOffline,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }

  @override
  List<Object?> get props => [
    selectedTab,
    selectedTimelineYear,
    favoritesSortOrder,
    status,
    timeline,
    albums,
    people,
    favorites,
    memories,
    hasLoadedTimeline,
    hasLoadedAlbums,
    hasLoadedPeople,
    hasLoadedFavorites,
    hasLoadedMemories,
    timelineNextPage,
    favoritesNextPage,
    isLoadingMore,
    errorMessage,
    isOffline,
    lastUpdatedAt,
  ];
}
