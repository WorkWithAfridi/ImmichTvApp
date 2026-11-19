import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/viewer/data/immich_hls_session_repository.dart';

void main() {
  const playlistUrl =
      'https://photos.example.com/api/assets/asset-1/video/stream/main.m3u8';
  const headers = {'x-api-key': 'token'};

  test('extracts the session id from the main playlist', () async {
    final adapter = _RecordingAdapter(
      playlist:
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n'
          'https://photos.example.com/api/assets/asset-1/video/stream/'
          '7f3c2a90-1234-4abc-8def-0123456789ab/0/playlist.m3u8\n',
    );
    final repository = ImmichHlsSessionRepository(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final sessionId = await repository.resolveSessionId(
      playlistUrl,
      headers: headers,
    );

    expect(sessionId, '7f3c2a90-1234-4abc-8def-0123456789ab');
    expect(adapter.requests.single.method, 'GET');
  });

  test('returns null when the playlist has no session id', () async {
    final repository = ImmichHlsSessionRepository(
      dio: Dio()..httpClientAdapter = _RecordingAdapter(playlist: '#EXTM3U\n'),
    );

    expect(
      await repository.resolveSessionId(playlistUrl, headers: headers),
      isNull,
    );
  });

  test('ends a session using the asset stream endpoint', () async {
    final adapter = _RecordingAdapter(playlist: '#EXTM3U\n');
    final repository = ImmichHlsSessionRepository(
      dio: Dio()..httpClientAdapter = adapter,
    );

    await repository.endSession(
      mainPlaylistUrl: playlistUrl,
      sessionId: 'session-1',
      headers: headers,
    );

    expect(adapter.requests.single.method, 'DELETE');
    expect(
      adapter.requests.single.uri.toString(),
      'https://photos.example.com/api/assets/asset-1/video/stream/session-1',
    );
  });

  test('session teardown failures are swallowed', () async {
    final adapter = _RecordingAdapter(playlist: '#EXTM3U\n', failDelete: true);
    final repository = ImmichHlsSessionRepository(
      dio: Dio()..httpClientAdapter = adapter,
    );

    await expectLater(
      repository.endSession(
        mainPlaylistUrl: playlistUrl,
        sessionId: 'session-1',
        headers: headers,
      ),
      completes,
    );
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.playlist, this.failDelete = false});

  final String playlist;
  final bool failDelete;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'DELETE' && failDelete) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<int>(
          requestOptions: options,
          statusCode: 500,
        ),
      );
    }
    return ResponseBody.fromString(playlist, 200);
  }

  @override
  void close({bool force = false}) {}
}
