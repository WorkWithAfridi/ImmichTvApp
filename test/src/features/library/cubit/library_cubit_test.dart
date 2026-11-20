import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/album_summary.dart';
import 'package:immichtv/src/core/models/asset_sort_order.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/media_page.dart';
import 'package:immichtv/src/core/models/memory_summary.dart';
import 'package:immichtv/src/core/errors/app_exception.dart';
import 'package:immichtv/src/core/models/person_summary.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/core/repositories/media_repository.dart';
import 'package:immichtv/src/features/library/cubit/library_cubit.dart';
import 'package:immichtv/src/features/library/cubit/library_state.dart';

void main() {
  test(
    'refreshContent stays silent when timeline, albums, and favorites are unchanged',
    () async {
      final repository = _FakeMediaRepository();
      final cubit = LibraryCubit(repository, _session());
      addTearDown(cubit.close);

      await cubit.loadInitial();

      final emittedStates = <LibraryState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await cubit.refreshContent();

      expect(emittedStates, isEmpty);
    },
  );

  test(
    'refreshContent prepends refreshed first-page assets and preserves paginated items',
    () async {
      final repository = _FakeMediaRepository();
      final cubit = LibraryCubit(repository, _session());
      addTearDown(cubit.close);

      await cubit.loadInitial();
      await cubit.loadMore();

      expect(cubit.state.timeline.map((asset) => asset.id), [
        'asset-1',
        'asset-2',
        'asset-3',
      ]);

      repository.timelinePages = {
        null: MediaPage(
          items: [_asset('asset-0'), _asset('asset-1')],
          nextPage: '2',
        ),
        '2': MediaPage(items: [_asset('asset-3')]),
      };

      await cubit.refreshContent();

      expect(cubit.state.timeline.map((asset) => asset.id), [
        'asset-0',
        'asset-1',
        'asset-2',
        'asset-3',
      ]);
      expect(cubit.state.timelineNextPage, '2');
    },
  );

  test(
    'loadInitial still succeeds when supporting tabs fail but timeline loads',
    () async {
      final repository = _FakeMediaRepository()
        ..throwAlbums = true
        ..throwFavorites = true
        ..throwPeople = true;
      final cubit = LibraryCubit(repository, _session());
      addTearDown(cubit.close);

      await cubit.loadInitial();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.status, LibraryLoadStatus.success);
      expect(cubit.state.hasLoadedTimeline, isTrue);
      expect(cubit.state.timeline, isNotEmpty);
      expect(cubit.state.hasLoadedAlbums, isFalse);
      expect(cubit.state.hasLoadedFavorites, isFalse);
      expect(cubit.state.hasLoadedPeople, isFalse);
    },
  );

  test('updateFavoritesSortOrder refetches favorites with requested order', () async {
    final repository = _FakeMediaRepository();
    final cubit = LibraryCubit(repository, _session());
    addTearDown(cubit.close);

    await cubit.loadInitial();
    await cubit.updateFavoritesSortOrder(AssetSortOrder.oldestFirst);

    expect(cubit.state.favoritesSortOrder, AssetSortOrder.oldestFirst);
    expect(repository.lastFavoritesSortOrder, AssetSortOrder.oldestFirst);
  });

  test('fetchMoreForSlideshow appends and returns the next timeline page',
      () async {
    final cubit = LibraryCubit(_FakeMediaRepository(), _session());
    addTearDown(cubit.close);

    await cubit.loadInitial();
    final page = await cubit.fetchMoreForSlideshow();

    expect(page.items.map((asset) => asset.id), ['asset-3']);
    expect(page.hasMore, isFalse);
    expect(
      cubit.state.timeline.map((asset) => asset.id),
      ['asset-1', 'asset-2', 'asset-3'],
    );
  });

  test('successful load records when the library was last refreshed', () async {
    final cubit = LibraryCubit(_FakeMediaRepository(), _session());
    addTearDown(cubit.close);

    await cubit.loadInitial();

    expect(cubit.state.lastUpdatedAt, isNotNull);
    expect(cubit.state.isOffline, isFalse);
  });

  test('connectivity failure during initial load marks the library offline',
      () async {
    final repository = _FakeMediaRepository()
      ..throwConnectivityOnTimelineRefresh = true;
    final cubit = LibraryCubit(repository, _session());
    addTearDown(cubit.close);

    await cubit.loadInitial();

    expect(cubit.state.status, LibraryLoadStatus.failure);
    expect(cubit.state.isOffline, isTrue);
  });

  test('background refresh failure keeps cached items and shows offline state',
      () async {
    final repository = _FakeMediaRepository();
    final cubit = LibraryCubit(repository, _session());
    addTearDown(cubit.close);

    await cubit.loadInitial();
    final cachedTimeline = cubit.state.timeline;
    repository.throwConnectivityOnTimelineRefresh = true;

    await cubit.refreshContent();

    expect(cubit.state.status, LibraryLoadStatus.success);
    expect(cubit.state.timeline, cachedTimeline);
    expect(cubit.state.isOffline, isTrue);

    repository.throwConnectivityOnTimelineRefresh = false;
    await cubit.retry();

    expect(cubit.state.isOffline, isFalse);
    expect(cubit.state.lastUpdatedAt, isNotNull);
  });
}

class _FakeMediaRepository implements MediaRepository {
  Map<String?, MediaPage<AssetSummary>> timelinePages = {
    null: MediaPage(
      items: [_asset('asset-1'), _asset('asset-2')],
      nextPage: '2',
    ),
    '2': MediaPage(items: [_asset('asset-3')]),
  };

  Map<String?, MediaPage<AssetSummary>> favoritePages = {
    null: MediaPage(items: [_asset('favorite-1')]),
  };

  List<AlbumSummary> albums = const [
    AlbumSummary(id: 'album-1', name: 'Summer Trip', assetCount: 42),
  ];

  List<PersonSummary> people = const [
    PersonSummary(
      id: 'person-1',
      name: 'Avery',
      assetCount: 3,
      thumbnailUrls: [
        'https://photos.example.com/api/people/person-1/thumbnail',
      ],
    ),
  ];
  bool throwAlbums = false;
  bool throwFavorites = false;
  bool throwPeople = false;
  bool throwConnectivityOnTimelineRefresh = false;
  AssetSortOrder lastFavoritesSortOrder = AssetSortOrder.newestFirst;

  @override
  Future<List<AlbumSummary>> fetchAlbums(AuthenticatedSession session) async {
    if (throwAlbums) {
      throw const AppException('albums failed');
    }
    return albums;
  }

  @override
  Future<List<MemorySummary>> fetchMemories(AuthenticatedSession session) async =>
      const <MemorySummary>[];

  @override
  Future<List<PersonSummary>> fetchPeople(AuthenticatedSession session) async {
    if (throwPeople) {
      throw const AppException('people failed');
    }
    return people;
  }

  @override
  Future<MediaPage<AssetSummary>> fetchAlbumAssetsPage(
    AuthenticatedSession session, {
    required String albumId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => MediaPage(items: [_asset('album-$albumId-1')]);

  @override
  Future<MediaPage<AssetSummary>> fetchFavoritesPage(
    AuthenticatedSession session, {
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 60,
  }) async {
    lastFavoritesSortOrder = sortOrder;
    if (throwFavorites) {
      throw const AppException('favorites failed');
    }
    return favoritePages[page] ?? const MediaPage(items: []);
  }

  @override
  Future<MediaPage<AssetSummary>> fetchPersonAssetsPage(
    AuthenticatedSession session, {
    required String personId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => MediaPage(items: [_asset('person-$personId-1')]);

  @override
  Future<MediaPage<AssetSummary>> fetchTimelinePage(
    AuthenticatedSession session, {
    String? page,
    int pageSize = 60,
    int? year,
  }) async {
    if (throwConnectivityOnTimelineRefresh && (page == null || page == '1')) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/search/metadata'),
        reason: 'connection refused',
      );
    }
    return timelinePages[page] ?? const MediaPage(items: []);
  }
}

AuthenticatedSession _session() {
  return AuthenticatedSession(
    serverConfig: ServerConfig(
      rawInput: 'https://photos.example.com',
      serverUrl: Uri.parse('https://photos.example.com'),
      apiUrl: Uri.parse('https://photos.example.com/api'),
    ),
    accessToken: 'token',
    user: const UserProfile(
      id: 'user-1',
      email: 'family@example.com',
      name: 'Living Room',
    ),
  );
}

AssetSummary _asset(String id) {
  final createdAt = switch (id) {
    'asset-0' => DateTime(2026, 11, 12),
    'asset-1' => DateTime(2026, 11, 11),
    'asset-2' => DateTime(2026, 11, 10),
    'asset-3' => DateTime(2026, 11, 9),
    _ => DateTime(2026, 11, 8),
  };

  return AssetSummary(
    id: id,
    thumbnailUrls: [
      'https://photos.example.com/api/assets/$id/thumbnail?size=preview',
      'https://photos.example.com/api/assets/$id/thumbnail?size=thumbnail',
    ],
    displayUrls: ['https://photos.example.com/api/assets/$id/original'],
    type: 'IMAGE',
    createdAt: createdAt,
  );
}
