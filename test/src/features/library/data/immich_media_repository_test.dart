import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/core/models/place_summary.dart';
import 'package:immichtv/src/core/repositories/playback_preferences.dart';
import 'package:immichtv/src/core/models/server_capabilities.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/features/library/data/immich_media_repository.dart';

void main() {
  test('timeline year filters include an ISO 8601 UTC timezone', () async {
    final adapter = _RecordingHttpClientAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = ImmichMediaRepository(dio: dio);

    await repository.fetchTimelinePage(_session(), year: 2025);

    expect(adapter.requestData, hasLength(1));
    expect(
      adapter.requestData.single,
      containsPair('takenAfter', '2025-01-01T00:00:00.000Z'),
    );
    expect(
      adapter.requestData.single,
      containsPair('takenBefore', '2025-12-31T23:59:59.999Z'),
    );
    expect(adapter.requestData.single, containsPair('visibility', 'timeline'));
  });

  test('timeline sends a numeric page returned by Immich', () async {
    final adapter = _RecordingHttpClientAdapter(
      responses: [
        _searchResponse(nextPage: '2'),
        _searchResponse(nextPage: null),
      ],
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = ImmichMediaRepository(dio: dio);

    final firstPage = await repository.fetchTimelinePage(
      _session(),
      year: 2025,
    );
    await repository.fetchTimelinePage(
      _session(),
      page: firstPage.nextPage,
      year: 2025,
    );

    expect(firstPage.nextPage, '2');
    expect(adapter.requestData, hasLength(2));
    expect(adapter.requestData.last, containsPair('page', 2));
    expect(adapter.requestData.last['page'], isA<int>());
  });

  test('people follows every page from the current Immich response', () async {
    final adapter = _RecordingHttpClientAdapter(
      responses: [
        _jsonResponse({
          'people': [
            {'id': 'person-1', 'name': 'Ada'},
          ],
          'hasNextPage': true,
          'hidden': 0,
          'total': 2,
        }),
        _jsonResponse({
          'people': [
            {'id': 'person-2', 'name': 'Grace'},
          ],
          'hasNextPage': false,
          'hidden': 0,
          'total': 2,
        }),
      ],
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = ImmichMediaRepository(dio: dio);

    final people = await repository.fetchPeople(_session());

    expect(people.map((person) => person.id), ['person-1', 'person-2']);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.queryParameters, {'page': 1, 'size': 100});
    expect(adapter.requests.last.queryParameters, {'page': 2, 'size': 100});
  });

  test('places come from the city endpoint and carry location data', () async {
    final adapter = _RecordingHttpClientAdapter(
      responses: [
        _jsonResponse([
          {
            'id': 'city-asset',
            'type': 'IMAGE',
            'fileCreatedAt': '2025-06-01T12:00:00.000Z',
            'exifInfo': {'city': 'Lisbon', 'state': 'Lisbon', 'country': 'Portugal'},
          },
        ]),
      ],
    );
    final session = _session(
      capabilities: const ServerCapabilities(major: 3, mapEnabled: true),
    );

    final places = await ImmichMediaRepository(
      dio: Dio()..httpClientAdapter = adapter,
    ).fetchPlaces(session);

    expect(places, hasLength(1));
    expect(places.single.city, 'Lisbon');
    expect(places.single.country, 'Portugal');
    expect(adapter.requests.single.uri.toString(),
        'https://photos.example.com/api/search/cities');
  });

  test('place assets are searched by city with the map gate applied', () async {
    final adapter = _RecordingHttpClientAdapter(
      responses: [_jsonResponse({'assets': {'items': [], 'count': 0}})],
    );
    final repository = ImmichMediaRepository(
      dio: Dio()..httpClientAdapter = adapter,
    );
    final session = _session(
      capabilities: const ServerCapabilities(major: 3, mapEnabled: true),
    );
    final place = PlaceSummary(
      id: 'Lisbon|Portugal',
      city: 'Lisbon',
      state: 'Lisbon',
      country: 'Portugal',
      preview: AssetSummary(
        id: 'preview',
        thumbnailUrls: [],
        displayUrls: [],
        type: 'IMAGE',
        createdAt: DateTime.utc(2025),
      ),
    );

    await repository.fetchPlaceAssetsPage(session, place: place);

    expect(adapter.requestData.single, containsPair('city', 'Lisbon'));
    expect(adapter.requestData.single, containsPair('country', 'Portugal'));
  });

  test('places are skipped when the server has map disabled', () async {
    final adapter = _RecordingHttpClientAdapter();
    final repository = ImmichMediaRepository(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final places = await repository.fetchPlaces(
      _session(
        capabilities: const ServerCapabilities(major: 3, mapEnabled: false),
      ),
    );

    expect(places, isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('videos expose the HLS playlist on servers that support it', () async {
    final adapter = _RecordingHttpClientAdapter(
      responses: [_searchResponse(nextPage: null, type: 'VIDEO')],
    );
    final session = _session(
      capabilities: const ServerCapabilities(major: 3, minor: 0, patch: 0),
    );

    final page = await ImmichMediaRepository(
      dio: Dio()..httpClientAdapter = adapter,
      playbackPreferences: const _EnabledPlaybackPreferences(),
    ).fetchTimelinePage(session, year: 2025);

    expect(
      page.items.first.hlsUrl,
      'https://photos.example.com/api/assets/asset-last/video/stream/main.m3u8',
    );
  });

  test('HLS is hidden on servers older than v3', () async {
    final adapter = _RecordingHttpClientAdapter(
      responses: [_searchResponse(nextPage: null, type: 'VIDEO')],
    );
    final session = _session(
      capabilities: const ServerCapabilities(major: 2, minor: 7, patch: 0),
    );

    final page = await ImmichMediaRepository(
      dio: Dio()..httpClientAdapter = adapter,
    ).fetchTimelinePage(session, year: 2025);

    expect(page.items.first.hlsUrl, isNull);
  });

  test('memories resolve embedded assets and carry their data', () async {
    final adapter = _RecordingHttpClientAdapter(
      responses: [
        _jsonResponse([
          {
            'id': 'memory-1',
            'type': 'ON_THIS_DAY',
            'memoryAt': '2023-11-19T10:00:00.000Z',
            'data': {'year': 2023},
            'assets': [
              {
                'id': 'memory-asset-1',
                'type': 'IMAGE',
                'fileCreatedAt': '2023-11-19T10:00:00.000Z',
              },
            ],
          },
        ]),
      ],
    );
    final repository = ImmichMediaRepository(dio: Dio()..httpClientAdapter = adapter);

    final memories = await repository.fetchMemories(_session());

    expect(memories, hasLength(1));
    expect(memories.single.title, '2023');
    expect(memories.single.assets.single.id, 'memory-asset-1');
    expect(
      adapter.requests.single.uri.toString(),
      'https://photos.example.com/api/memories?size=50',
    );
    expect(adapter.requests.single.queryParameters, {'size': 50});
  });

  test('memories are skipped entirely on servers without support', () async {
    final adapter = _RecordingHttpClientAdapter();
    final session = _session(
      capabilities: const ServerCapabilities(major: 1, minor: 140, patch: 0),
    );

    final memories = await ImmichMediaRepository(
      dio: Dio()..httpClientAdapter = adapter,
    ).fetchMemories(session);

    expect(memories, isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('grid uses thumbnail before preview without changing display URLs', () async {
    final adapter = _RecordingHttpClientAdapter(
      responses: [_searchResponse(nextPage: null)],
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = ImmichMediaRepository(dio: dio);

    final page = await repository.fetchTimelinePage(_session(), year: 2025);
    final asset = page.items.single;

    expect(asset.thumbnailUrls, [
      'https://photos.example.com/api/assets/asset-last/thumbnail?size=thumbnail',
      'https://photos.example.com/api/assets/asset-last/thumbnail?size=preview',
    ]);
    expect(asset.displayUrls, [
      'https://photos.example.com/api/assets/asset-last/thumbnail?size=preview',
      'https://photos.example.com/api/assets/asset-last/thumbnail?size=thumbnail',
      'https://photos.example.com/api/assets/asset-last/original',
    ]);
  });
}

ResponseBody _searchResponse({
  required String? nextPage,
  String type = 'IMAGE',
}) {
  return _jsonResponse({
    'assets': {
      'items': [
        {
          'id': 'asset-${nextPage ?? 'last'}',
          'type': type,
          'fileCreatedAt': '2025-06-01T12:00:00.000Z',
        },
      ],
      'nextPage': nextPage,
    },
  });
}

ResponseBody _jsonResponse(Object body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

AuthenticatedSession _session({ServerCapabilities? capabilities}) {
  return AuthenticatedSession(
    capabilities: capabilities ?? const ServerCapabilities(),
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

class _EnabledPlaybackPreferences implements PlaybackPreferences {
  const _EnabledPlaybackPreferences();

  @override
  bool get hlsEnabled => true;

  @override
  Future<void> load() async {}

  @override
  Future<void> setHlsEnabled(bool enabled) async {}
}

class _RecordingHttpClientAdapter implements HttpClientAdapter {
  _RecordingHttpClientAdapter({List<ResponseBody>? responses})
    : _responses = responses ?? const [];

  final List<ResponseBody> _responses;
  final List<Map<String, dynamic>> requestData = [];
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.data is Map) {
      requestData.add(Map<String, dynamic>.from(options.data as Map));
    }
    if (_responses.isNotEmpty) {
      return _responses[requests.length - 1];
    }
    return ResponseBody.fromString(
      jsonEncode({
        'assets': {'items': <Object>[], 'nextPage': null},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}
