import '../../../core/models/album_summary.dart';
import '../../../core/models/asset_sort_order.dart';
import '../../../core/models/authenticated_session.dart';
import '../../../core/models/asset_summary.dart';
import '../../../core/models/media_page.dart';
import '../../../core/models/memory_summary.dart';
import '../../../core/models/person_summary.dart';
import '../../../core/models/place_summary.dart';
import '../../../core/repositories/media_repository.dart';

class MockMediaRepository implements MediaRepository {
  MockMediaRepository()
    : _timeline = _buildTimeline(),
      _favorites = _buildFavorites(),
      _albums = _buildAlbums(),
      _people = _buildPeople(),
      _memories = _buildMemories(_buildTimeline()),
      _places = _buildPlaces();

  final List<AssetSummary> _timeline;
  final List<AssetSummary> _favorites;
  final List<AlbumSummary> _albums;
  final List<PersonSummary> _people;
  final List<MemorySummary> _memories;
  final List<PlaceSummary> _places;

  static const _pageSizeDefault = 60;

  @override
  Future<List<AlbumSummary>> fetchAlbums(AuthenticatedSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    return _albums;
  }

  @override
  Future<List<PersonSummary>> fetchPeople(AuthenticatedSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    return _people;
  }

  @override
  Future<List<MemorySummary>> fetchMemories(AuthenticatedSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    return _memories;
  }

  @override
  Future<List<PlaceSummary>> fetchPlaces(AuthenticatedSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    return _places;
  }

  @override
  Future<MediaPage<AssetSummary>> fetchPlaceAssetsPage(
    AuthenticatedSession session, {
    required PlaceSummary place,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = _pageSizeDefault,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final assets = _timeline
        .where(
          (asset) =>
              asset.city == place.city && asset.country == place.country,
        )
        .toList(growable: false);
    return _pageAssets(
      _sortedAssets(assets, sortOrder),
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<MediaPage<AssetSummary>> fetchAlbumAssetsPage(
    AuthenticatedSession session, {
    required String albumId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = _pageSizeDefault,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    return _pageAssets(
      _sortedAssets(_buildAlbumAssets(albumId), sortOrder),
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<MediaPage<AssetSummary>> fetchFavoritesPage(
    AuthenticatedSession session, {
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = _pageSizeDefault,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    return _pageAssets(
      _sortedAssets(_favorites, sortOrder),
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<MediaPage<AssetSummary>> fetchPersonAssetsPage(
    AuthenticatedSession session, {
    required String personId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = _pageSizeDefault,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    return _pageAssets(
      _sortedAssets(_buildPersonAssets(personId), sortOrder),
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<MediaPage<AssetSummary>> fetchTimelinePage(
    AuthenticatedSession session, {
    String? page,
    int pageSize = _pageSizeDefault,
    int? year,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 340));
    final filteredTimeline = year == null
        ? _timeline
        : _timeline
              .where((asset) => asset.createdAt.year == year)
              .toList(growable: false);
    return _pageAssets(filteredTimeline, page: page, pageSize: pageSize);
  }

  MediaPage<AssetSummary> _pageAssets(
    List<AssetSummary> items, {
    required String? page,
    required int pageSize,
  }) {
    final pageIndex = int.tryParse(page ?? '1') ?? 1;
    final start = (pageIndex - 1) * pageSize;
    if (start >= items.length) {
      return const MediaPage(items: []);
    }

    final end = (start + pageSize).clamp(0, items.length);
    final nextPage = end < items.length ? '${pageIndex + 1}' : null;

    return MediaPage(items: items.sublist(start, end), nextPage: nextPage);
  }
}

List<AssetSummary> _sortedAssets(
  List<AssetSummary> assets,
  AssetSortOrder sortOrder,
) {
  final sorted = assets.toList(growable: false);
  return sorted..sort((a, b) {
    final compare = a.createdAt.compareTo(b.createdAt);
    return sortOrder == AssetSortOrder.oldestFirst ? compare : -compare;
  });
}

List<AssetSummary> _buildTimeline() {
  final items = <AssetSummary>[];
  final start = DateTime(2025, 4, 28, 18);
  final imageSeeds = [
    'immichtv-city-1',
    'immichtv-portrait-2',
    'immichtv-road-3',
    'immichtv-coast-4',
    'immichtv-mountain-5',
    'immichtv-river-6',
    'immichtv-studio-7',
    'immichtv-forest-8',
    'immichtv-night-9',
    'immichtv-interior-10',
    'immichtv-sunrise-11',
    'immichtv-travel-12',
  ];
  final videoUrls = [
    'https://samplelib.com/lib/preview/mp4/sample-5s.mp4',
    'https://samplelib.com/lib/preview/mp4/sample-10s.mp4',
    'https://samplelib.com/lib/preview/mp4/sample-15s.mp4',
  ];

  for (var index = 0; index < 180; index++) {
    final createdAt = start.subtract(Duration(hours: index * 7));
    final id = 'mock-asset-${index + 1}';
    final imageSeed = imageSeeds[index % imageSeeds.length];
    final isVideo = index % 11 == 0;
    final thumbnailUrl = _picsumSquareUrl(
      seed: isVideo ? 'video-thumb-$imageSeed' : imageSeed,
      size: 800,
    );
    final displayUrl = isVideo
        ? videoUrls[index % videoUrls.length]
        : _picsumSquareUrl(seed: '$imageSeed-full', size: 1600);
    items.add(
      AssetSummary(
        id: id,
        thumbnailUrls: [thumbnailUrl],
        displayUrls: [displayUrl],
        type: isVideo ? 'VIDEO' : 'IMAGE',
        createdAt: createdAt,
        requiresAuth: false,
      ),
    );
  }

  return items;
}

String _picsumSquareUrl({required String seed, required int size}) {
  return 'https://picsum.photos/seed/$seed/$size/$size';
}

List<MemorySummary> _buildMemories(List<AssetSummary> timeline) {
  if (timeline.isEmpty) {
    return const <MemorySummary>[];
  }

  const configurations = <Map<String, Object>>[
    {'title': '2023', 'subtitle': '3 years ago', 'count': 8},
    {'title': '2024', 'subtitle': '2 years ago', 'count': 10},
    {'title': 'Avery\'s birthday', 'subtitle': 'Last year', 'count': 6},
    {'title': '2025', 'subtitle': 'One year ago', 'count': 12},
  ];

  var start = 0;
  final memories = <MemorySummary>[];
  for (final configuration in configurations) {
    final count = configuration['count']! as int;
    final assets = timeline.skip(start).take(count).toList(growable: false);
    start += count;
    if (assets.isEmpty) {
      break;
    }
    memories.add(
      MemorySummary(
        id: 'mock-memory-${memories.length + 1}',
        title: configuration['title']! as String,
        subtitle: configuration['subtitle']! as String,
        memoryAt: assets.first.createdAt,
        assets: assets,
      ),
    );
  }
  return List<MemorySummary>.unmodifiable(memories);
}

List<PlaceSummary> _buildPlaces() {
  const locations = <Map<String, String>>[
    {'city': 'Lisbon', 'country': 'Portugal'},
    {'city': 'Kyoto', 'country': 'Japan'},
    {'city': 'Vancouver', 'country': 'Canada'},
    {'city': 'Cape Town', 'country': 'South Africa'},
  ];

  final places = <PlaceSummary>[];
  for (var index = 0; index < locations.length; index++) {
    final location = locations[index];
    final matching = _buildTimeline()
        .where((asset) => int.parse(asset.id.split('-').last) % 4 == index)
        .map(
          (asset) => AssetSummary(
            id: asset.id,
            thumbnailUrls: asset.thumbnailUrls,
            displayUrls: asset.displayUrls,
            type: asset.type,
            createdAt: asset.createdAt,
            requiresAuth: false,
            city: location['city'],
            country: location['country'],
          ),
        )
        .toList(growable: false);
    if (matching.isEmpty) {
      continue;
    }
    places.add(
      PlaceSummary(
        id: '${location['city']}|${location['country']}',
        city: location['city']!,
        state: '',
        country: location['country']!,
        preview: matching.first,
      ),
    );
  }
  return List<PlaceSummary>.unmodifiable(places);
}

List<AssetSummary> _buildFavorites() {
  final timeline = _buildTimeline();
  return timeline
      .where((asset) => int.parse(asset.id.split('-').last) % 7 == 0)
      .take(24)
      .toList(growable: false);
}

List<AlbumSummary> _buildAlbums() {
  return const [
    AlbumSummary(id: 'album-1', name: 'Summer by the Coast', assetCount: 184),
    AlbumSummary(id: 'album-2', name: 'Family Weekend', assetCount: 96),
    AlbumSummary(id: 'album-3', name: 'Kitchen Experiments', assetCount: 58),
    AlbumSummary(id: 'album-4', name: 'City Walks at Night', assetCount: 132),
    AlbumSummary(id: 'album-5', name: 'Mountains and Cabins', assetCount: 73),
    AlbumSummary(id: 'album-6', name: 'Portrait Favorites', assetCount: 41),
  ];
}

List<PersonSummary> _buildPeople() {
  return [
    PersonSummary(
      id: 'person-1',
      name: 'Avery',
      assetCount: 64,
      thumbnailUrls: const [
        'mock://person-avery?palette=dusk&variant=thumbnail',
      ],
    ),
    PersonSummary(
      id: 'person-2',
      name: 'Jordan',
      assetCount: 48,
      thumbnailUrls: const [
        'mock://person-jordan?palette=forest&variant=thumbnail',
      ],
    ),
    PersonSummary(
      id: 'person-3',
      name: 'Mila',
      assetCount: 31,
      thumbnailUrls: const [
        'mock://person-mila?palette=ember&variant=thumbnail',
      ],
    ),
    PersonSummary(
      id: 'person-4',
      name: 'Noah',
      assetCount: 27,
      thumbnailUrls: const [
        'mock://person-noah?palette=sunrise&variant=thumbnail',
      ],
    ),
    PersonSummary(
      id: 'person-5',
      name: 'Sofia',
      assetCount: 19,
      thumbnailUrls: const [
        'mock://person-sofia?palette=sea-glass&variant=thumbnail',
      ],
    ),
  ];
}

List<AssetSummary> _buildAlbumAssets(String albumId) {
  final timeline = _buildTimeline();

  final albumOffsets = <String, int>{
    'album-1': 0,
    'album-2': 8,
    'album-3': 16,
    'album-4': 24,
    'album-5': 32,
    'album-6': 40,
  };

  final start = albumOffsets[albumId] ?? 0;
  final end = (start + 18).clamp(0, timeline.length);
  if (start >= end) {
    return const [];
  }

  return timeline.sublist(start, end);
}

List<AssetSummary> _buildPersonAssets(String personId) {
  final timeline = _buildTimeline();

  final personOffsets = <String, int>{
    'person-1': 4,
    'person-2': 22,
    'person-3': 40,
    'person-4': 58,
    'person-5': 76,
  };

  final start = personOffsets[personId] ?? 0;
  final end = (start + 16).clamp(0, timeline.length);
  if (start >= end) {
    return const [];
  }

  return timeline.sublist(start, end);
}
