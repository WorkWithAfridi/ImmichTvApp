import 'package:dio/dio.dart';

import '../../../core/config/demo_mode.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/album_summary.dart';
import '../../../core/models/asset_sort_order.dart';
import '../../../core/models/authenticated_session.dart';
import '../../../core/models/asset_summary.dart';
import '../../../core/models/media_page.dart';
import '../../../core/models/person_summary.dart';
import '../../../core/network/immich_headers.dart';
import '../../../core/repositories/media_repository.dart';
import '../../mock/data/mock_media_repository.dart';

class ImmichMediaRepository implements MediaRepository {
  ImmichMediaRepository({required Dio dio})
    : _dio = dio,
      _mockMediaRepository = MockMediaRepository();

  final Dio _dio;
  final MockMediaRepository _mockMediaRepository;

  @override
  Future<List<AlbumSummary>> fetchAlbums(AuthenticatedSession session) async {
    if (DemoMode.matchesServerUrl(session.serverConfig.serverUrl)) {
      return _mockMediaRepository.fetchAlbums(session);
    }

    final response = await _dio.get<List<dynamic>>(
      session.serverConfig.apiEndpoint('albums').toString(),
      options: Options(headers: ImmichHeaders.sessionHeaders(session)),
    );

    final items = response.data ?? const [];
    final albums = items
        .whereType<Map<String, dynamic>>()
        .map(_mapAlbum)
        .whereType<AlbumSummary>()
        .toList(growable: false);
    final sortedAlbums = albums.toList(growable: false)
      ..sort((a, b) {
        final assetCountCompare = b.assetCount.compareTo(a.assetCount);
        if (assetCountCompare != 0) {
          return assetCountCompare;
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return sortedAlbums;
  }

  @override
  Future<List<PersonSummary>> fetchPeople(AuthenticatedSession session) async {
    if (DemoMode.matchesServerUrl(session.serverConfig.serverUrl)) {
      return _mockMediaRepository.fetchPeople(session);
    }

    const pageSize = 100;
    final items = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final response = await _dio.get<dynamic>(
        session.serverConfig.apiEndpoint('people').toString(),
        queryParameters: {'page': page, 'size': pageSize},
        options: Options(headers: ImmichHeaders.sessionHeaders(session)),
      );
      final pageItems = _extractPeopleMaps(response.data);
      items.addAll(pageItems);

      final hasNextPage = response.data is Map<String, dynamic>
          ? response.data['hasNextPage'] == true
          : false;
      if (!hasNextPage || pageItems.isEmpty) {
        break;
      }
      page += 1;
    }
    final people = items
        .map((item) => _mapPerson(item, session))
        .whereType<PersonSummary>()
        .toList(growable: false);
    final sortedPeople = people.toList(growable: false)
      ..sort((a, b) {
        final assetCountCompare = b.assetCount.compareTo(a.assetCount);
        if (assetCountCompare != 0) {
          return assetCountCompare;
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return sortedPeople;
  }

  @override
  Future<MediaPage<AssetSummary>> fetchAlbumAssetsPage(
    AuthenticatedSession session, {
    required String albumId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async {
    if (DemoMode.matchesServerUrl(session.serverConfig.serverUrl)) {
      return _mockMediaRepository.fetchAlbumAssetsPage(
        session,
        albumId: albumId,
        sortOrder: sortOrder,
        page: page,
        pageSize: pageSize,
      );
    }

    final pageNumber = int.tryParse(page ?? '1') ?? 1;
    final response = await _dio.post<dynamic>(
      session.serverConfig.apiEndpoint('search/metadata').toString(),
      data: {
        'albumIds': [albumId],
        'page': pageNumber,
        'size': pageSize,
        'order': sortOrder.apiValue,
        'visibility': 'timeline',
      },
      options: Options(
        headers: {
          ...ImmichHeaders.sessionHeaders(session),
          'Content-Type': 'application/json',
        },
      ),
    );

    final items = _extractAssetMaps(response.data);
    return MediaPage(
      items: items
          .map((item) => _mapAsset(item, session))
          .whereType<AssetSummary>()
          .toList(growable: false),
      nextPage:
          _extractNextPage(response.data) ??
          _extractCountBasedNextPage(
            response.data,
            currentPage: pageNumber,
            pageSize: pageSize,
            currentItemCount: items.length,
          ),
    );
  }

  @override
  Future<MediaPage<AssetSummary>> fetchPersonAssetsPage(
    AuthenticatedSession session, {
    required String personId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async {
    if (DemoMode.matchesServerUrl(session.serverConfig.serverUrl)) {
      return _mockMediaRepository.fetchPersonAssetsPage(
        session,
        personId: personId,
        sortOrder: sortOrder,
        page: page,
        pageSize: pageSize,
      );
    }

    final pageNumber = int.tryParse(page ?? '1') ?? 1;
    final response = await _dio.post<dynamic>(
      session.serverConfig.apiEndpoint('search/metadata').toString(),
      data: {
        'personIds': [personId],
        'page': pageNumber,
        'size': pageSize,
        'order': sortOrder.apiValue,
        'visibility': 'timeline',
      },
      options: Options(
        headers: {
          ...ImmichHeaders.sessionHeaders(session),
          'Content-Type': 'application/json',
        },
      ),
    );

    final items = _extractAssetMaps(response.data);
    return MediaPage(
      items: items
          .map((item) => _mapAsset(item, session))
          .whereType<AssetSummary>()
          .toList(growable: false),
      nextPage:
          _extractNextPage(response.data) ??
          _extractCountBasedNextPage(
            response.data,
            currentPage: pageNumber,
            pageSize: pageSize,
            currentItemCount: items.length,
          ),
    );
  }

  @override
  Future<MediaPage<AssetSummary>> fetchFavoritesPage(
    AuthenticatedSession session, {
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 30,
  }) async {
    if (DemoMode.matchesServerUrl(session.serverConfig.serverUrl)) {
      return _mockMediaRepository.fetchFavoritesPage(
        session,
        sortOrder: sortOrder,
        page: page,
        pageSize: pageSize,
      );
    }

    logger.info(
      'Fetching favorite assets for ${session.user.email} page ${page ?? '1'}',
    );
    final Map<String, dynamic> requestBody = {
      'isFavorite': true,
      'size': pageSize,
      'order': sortOrder.apiValue,
    };
    if (page != null) {
      requestBody['page'] = int.tryParse(page) ?? page;
    }
    final response = await _dio.post<dynamic>(
      session.serverConfig.apiEndpoint('search/metadata').toString(),
      data: requestBody,
      options: Options(
        headers: {
          ...ImmichHeaders.sessionHeaders(session),
          'Content-Type': 'application/json',
        },
      ),
    );

    final items = _extractAssetMaps(response.data);
    logger.info('Favorite assets payload returned ${items.length} items');
    return MediaPage(
      items: items
          .map((item) => _mapAsset(item, session))
          .whereType<AssetSummary>()
          .toList(growable: false),
      nextPage: _extractNextPage(response.data),
    );
  }

  @override
  Future<MediaPage<AssetSummary>> fetchTimelinePage(
    AuthenticatedSession session, {
    String? page,
    int pageSize = 30,
    int? year,
  }) async {
    if (DemoMode.matchesServerUrl(session.serverConfig.serverUrl)) {
      return _mockMediaRepository.fetchTimelinePage(
        session,
        page: page,
        pageSize: pageSize,
        year: year,
      );
    }

    logger.info(
      'Fetching timeline assets for ${session.user.email} page ${page ?? '1'} year ${year?.toString() ?? 'all'}',
    );
    final searchTimeline = await _fetchTimelineViaSearchMetadata(
      session,
      page: page,
      pageSize: pageSize,
      year: year,
    );
    logger.info(
      'Timeline asset search returned ${searchTimeline.items.length} assets',
    );
    return searchTimeline;
  }

  Future<MediaPage<AssetSummary>> _fetchTimelineViaSearchMetadata(
    AuthenticatedSession session, {
    String? page,
    required int pageSize,
    int? year,
  }) async {
    final Map<String, dynamic> requestBody = {
      'size': pageSize,
      'visibility': 'timeline',
      'order': 'desc',
    };
    if (page != null) {
      requestBody['page'] = int.tryParse(page) ?? page;
    }
    if (year != null) {
      requestBody['takenAfter'] = DateTime.utc(year, 1, 1).toIso8601String();
      requestBody['takenBefore'] = DateTime.utc(
        year + 1,
        1,
        1,
      ).subtract(const Duration(milliseconds: 1)).toIso8601String();
    }
    final response = await _dio.post<dynamic>(
      session.serverConfig.apiEndpoint('search/metadata').toString(),
      data: requestBody,
      options: Options(
        headers: {
          ...ImmichHeaders.sessionHeaders(session),
          'Content-Type': 'application/json',
        },
      ),
    );

    final items = _extractAssetMaps(response.data);
    return MediaPage(
      items: items
          .map((item) => _mapAsset(item, session))
          .whereType<AssetSummary>()
          .toList(growable: false),
      nextPage: _extractNextPage(response.data),
    );
  }

  String? _extractNextPage(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final directNextPage = payload['nextPage'];
      if (directNextPage != null && directNextPage.toString().isNotEmpty) {
        return directNextPage.toString();
      }

      for (final key in const ['assets', 'items', 'results', 'data']) {
        final nested = payload[key];
        if (nested is Map<String, dynamic>) {
          final nestedNextPage = _extractNextPage(nested);
          if (nestedNextPage != null && nestedNextPage.isNotEmpty) {
            return nestedNextPage;
          }
        }
      }
    }

    return null;
  }

  String? _extractCountBasedNextPage(
    dynamic payload, {
    required int currentPage,
    required int pageSize,
    required int currentItemCount,
  }) {
    if (payload is Map<String, dynamic>) {
      final rawCount = payload['count'];
      final count = rawCount is int
          ? rawCount
          : int.tryParse(rawCount?.toString() ?? '');
      if (count != null) {
        return count > currentPage * pageSize ? '${currentPage + 1}' : null;
      }
    }

    return currentItemCount >= pageSize ? '${currentPage + 1}' : null;
  }

  List<Map<String, dynamic>> _extractAssetMaps(dynamic payload) {
    if (payload is List) {
      return payload.whereType<Map<String, dynamic>>().toList(growable: false);
    }

    if (payload is Map<String, dynamic>) {
      final directItems = payload['items'];
      if (directItems is List) {
        return directItems.whereType<Map<String, dynamic>>().toList(
          growable: false,
        );
      }

      final candidates = <dynamic>[
        payload['assets'],
        payload['items'],
        payload['results'],
        payload['data'],
      ];

      for (final nested in candidates) {
        if (nested is List) {
          return nested.whereType<Map<String, dynamic>>().toList(
            growable: false,
          );
        }

        if (nested is Map<String, dynamic>) {
          final nestedItems = _extractAssetMaps(nested);
          if (nestedItems.isNotEmpty) {
            return nestedItems;
          }
        }
      }
    }

    return const [];
  }

  List<Map<String, dynamic>> _extractPeopleMaps(dynamic payload) {
    if (payload is List) {
      return payload.whereType<Map<String, dynamic>>().toList(growable: false);
    }

    if (payload is Map<String, dynamic>) {
      final candidates = <dynamic>[
        payload['people'],
        payload['items'],
        payload['results'],
        payload['data'],
      ];

      for (final nested in candidates) {
        if (nested is List) {
          return nested.whereType<Map<String, dynamic>>().toList(
            growable: false,
          );
        }
      }
    }

    return const [];
  }

  AlbumSummary? _mapAlbum(Map<String, dynamic> item) {
    final id = item['id'] as String?;
    final name = (item['albumName'] ?? item['name'] ?? item['title'])
        ?.toString();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }

    final assetCountValue = item['assetCount'];
    final assetCount = assetCountValue is int
        ? assetCountValue
        : int.tryParse(assetCountValue?.toString() ?? '') ?? 0;

    return AlbumSummary(id: id, name: name, assetCount: assetCount);
  }

  PersonSummary? _mapPerson(
    Map<String, dynamic> item,
    AuthenticatedSession session,
  ) {
    final id = item['id'] as String?;
    final rawName = (item['name'] ?? item['personName'] ?? item['title'])
        ?.toString()
        .trim();
    if (id == null || id.isEmpty) {
      return null;
    }

    final assetCountValue =
        item['assetCount'] ?? item['assetsCount'] ?? item['photoCount'];
    final assetCount = assetCountValue is int
        ? assetCountValue
        : int.tryParse(assetCountValue?.toString() ?? '') ?? 0;

    final name = (rawName == null || rawName.isEmpty)
        ? 'Unnamed person'
        : rawName;

    return PersonSummary(
      id: id,
      name: name,
      assetCount: assetCount,
      thumbnailUrls: [
        session.serverConfig.apiEndpoint('people/$id/thumbnail').toString(),
      ],
    );
  }

  AssetSummary? _mapAsset(
    Map<String, dynamic> item,
    AuthenticatedSession session,
  ) {
    final id = item['id'] as String?;
    if (id == null || id.isEmpty) {
      return null;
    }

    final type = (item['type'] ?? item['originalPath'] ?? 'asset').toString();
    final createdAtRaw =
        item['localDateTime'] ??
        item['fileCreatedAt'] ??
        item['createdAt'] ??
        item['date'];
    final createdAt = DateTime.tryParse(createdAtRaw?.toString() ?? '');

    return AssetSummary(
      id: id,
      thumbnailUrls: _buildThumbnailUrls(session, id, type),
      displayUrls: _buildDisplayUrls(session, id, type),
      type: type,
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  List<String> _buildThumbnailUrls(
    AuthenticatedSession session,
    String id,
    String type,
  ) {
    final baseThumbnail = session.serverConfig.apiEndpoint(
      'assets/$id/thumbnail',
    );
    return <String>[
      baseThumbnail
          .replace(queryParameters: const {'size': 'thumbnail'})
          .toString(),
      baseThumbnail
          .replace(queryParameters: const {'size': 'preview'})
          .toString(),
    ];
  }

  List<String> _buildDisplayUrls(
    AuthenticatedSession session,
    String id,
    String type,
  ) {
    if (type.toUpperCase().contains('VIDEO')) {
      return [
        session.serverConfig.apiEndpoint('assets/$id/original').toString(),
        session.serverConfig
            .apiEndpoint('assets/$id/thumbnail')
            .replace(queryParameters: const {'size': 'preview'})
            .toString(),
        session.serverConfig
            .apiEndpoint('assets/$id/video/playback')
            .toString(),
      ];
    }

    final previewUrl = session.serverConfig
        .apiEndpoint('assets/$id/thumbnail')
        .replace(queryParameters: const {'size': 'preview'})
        .toString();
    final thumbnailUrl = session.serverConfig
        .apiEndpoint('assets/$id/thumbnail')
        .replace(queryParameters: const {'size': 'thumbnail'})
        .toString();
    final originalUrl = session.serverConfig
        .apiEndpoint('assets/$id/original')
        .toString();

    return [previewUrl, thumbnailUrl, originalUrl];
  }
}
