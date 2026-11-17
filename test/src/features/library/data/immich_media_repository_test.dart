import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
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

ResponseBody _searchResponse({required String? nextPage}) {
  return _jsonResponse({
    'assets': {
      'items': [
        {
          'id': 'asset-${nextPage ?? 'last'}',
          'type': 'IMAGE',
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
