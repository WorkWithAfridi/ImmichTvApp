import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/server_capabilities.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/features/library/data/immich_asset_detail_repository.dart';

void main() {
  test('combines asset EXIF, metadata and OCR into one detail', () async {
    final adapter = _Adapter(
      bodies: {
        'https://photos.example.com/api/assets/asset-1': {
          'id': 'asset-1',
          'originalFileName': 'IMG_1.jpg',
          'exifInfo': {
            'description': 'A sunset',
            'make': 'Canon',
            'model': 'EOS',
            'city': 'Lisbon',
            'country': 'Portugal',
            'dateTimeOriginal': '2025-06-01T10:00:00.000Z',
          },
        },
        'https://photos.example.com/api/assets/asset-1/metadata': [
          {'key': 'Rating', 'value': '5'},
        ],
        'https://photos.example.com/api/assets/asset-1/ocr': [
          {'text': 'HELLO'},
          {'text': '   '},
        ],
      },
    );

    final detail = await ImmichAssetDetailRepository(
      dio: Dio()..httpClientAdapter = adapter,
    ).fetchDetail(
      _session(const ServerCapabilities(major: 3, ocrEnabled: true)),
      'asset-1',
    );

    expect(detail, isNotNull);
    expect(detail!.description, 'A sunset');
    expect(detail.camera, 'Canon EOS');
    expect(detail.location, 'Lisbon, Portugal');
    expect(detail.metadata, {'Rating': '5'});
    expect(detail.ocrTexts, ['HELLO']);
    expect(adapter.requests, hasLength(3));
  });

  test('skips OCR when the server has OCR disabled', () async {
    final adapter = _Adapter(
      bodies: {
        'https://photos.example.com/api/assets/asset-1': {
          'id': 'asset-1',
          'exifInfo': {},
        },
        'https://photos.example.com/api/assets/asset-1/metadata': [],
      },
    );

    await ImmichAssetDetailRepository(
      dio: Dio()..httpClientAdapter = adapter,
    ).fetchDetail(
      _session(const ServerCapabilities(major: 3, ocrEnabled: false)),
      'asset-1',
    );

    expect(
      adapter.requests.any((url) => url.endsWith('/ocr')),
      isFalse,
    );
  });
}

AuthenticatedSession _session(ServerCapabilities capabilities) {
  return AuthenticatedSession(
    serverConfig: ServerConfig(
      rawInput: 'https://photos.example.com',
      serverUrl: Uri.parse('https://photos.example.com'),
      apiUrl: Uri.parse('https://photos.example.com/api'),
    ),
    accessToken: 'token',
    user: const UserProfile(id: 'user', email: 'user@example.com', name: 'TV'),
    capabilities: capabilities,
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter({required this.bodies});

  final Map<String, Object> bodies;
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requests.add(url);
    final body = bodies[url];
    if (body == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<int>(requestOptions: options, statusCode: 404),
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}
