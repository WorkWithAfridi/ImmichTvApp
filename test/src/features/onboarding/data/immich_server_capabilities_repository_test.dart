import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/immich_auth_method.dart';
import 'package:immichtv/src/core/models/server_capabilities.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/features/onboarding/data/immich_server_capabilities_repository.dart';

void main() {
  test('combines version, media types, and user config into capabilities', () async {
    final dio = Dio()
      ..httpClientAdapter = _ProbeAdapter(
        responses: {
          'GET https://photos.example.com/api/server/version': {
            'major': 3,
            'minor': 2,
            'patch': 0,
          },
          'GET https://photos.example.com/api/server/media-types': {
            'video': ['video/mp4'],
          },
          'GET https://photos.example.com/api/config': {
            'map': {'enabled': true},
            'machineLearning': {
              'enabled': true,
              'ocr': {'enabled': true},
            },
          },
        },
      );

    final capabilities = await ImmichServerCapabilitiesRepository(
      dio: dio,
    ).fetch(_session());

    expect(capabilities.versionLabel, 'v3.2.0');
    expect(capabilities.supports(ServerFeature.map), isTrue);
    expect(capabilities.supports(ServerFeature.ocr), isTrue);
    expect(capabilities.supports(ServerFeature.hlsVideo), isTrue);
  });

  test('a failing or forbidden probe degrades to unknown capabilities', () async {
    final dio = Dio()
      ..httpClientAdapter = _ProbeAdapter(
        responses: {
          'GET https://photos.example.com/api/server/version': {'major': 2},
        },
      );

    final capabilities = await ImmichServerCapabilitiesRepository(
      dio: dio,
    ).fetch(_session());

    expect(capabilities.isKnown, isTrue);
    expect(capabilities.mapEnabled, isNull);
    expect(capabilities.supports(ServerFeature.map), isFalse);
    expect(capabilities.supports(ServerFeature.hlsVideo), isFalse);
  });
}

AuthenticatedSession _session() {
  return AuthenticatedSession(
    serverConfig: ServerConfig(
      rawInput: 'https://photos.example.com',
      serverUrl: Uri.parse('https://photos.example.com'),
      apiUrl: Uri.parse('https://photos.example.com/api'),
    ),
    accessToken: 'token',
    user: const UserProfile(id: 'id', email: 'user@example.com', name: 'User'),
    authMethod: ImmichAuthMethod.apiKey,
  );
}

class _ProbeAdapter implements HttpClientAdapter {
  _ProbeAdapter({required this.responses});

  final Map<String, Object> responses;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.uri}';
    final value = responses[key];
    if (value == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: 403,
          data: 'forbidden',
        ),
      );
    }
    return ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
