import 'package:dio/dio.dart';

import '../../../core/repositories/hls_session_repository.dart';

class ImmichHlsSessionRepository implements HlsSessionRepository {
  ImmichHlsSessionRepository({required Dio dio}) : _dio = dio;

  /// Matches the session id in `/assets/{id}/video/stream/{sessionId}/...`.
  static final _sessionIdPattern = RegExp(
    r'/video/stream/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/',
  );

  final Dio _dio;

  @override
  Future<String?> resolveSessionId(
    String mainPlaylistUrl, {
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.get<String>(
        mainPlaylistUrl,
        options: Options(
          headers: headers,
          extra: const {'skipRetry': true},
          responseType: ResponseType.plain,
        ),
      );
      final match = _sessionIdPattern.firstMatch(response.data ?? '');
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> endSession({
    required String mainPlaylistUrl,
    required String sessionId,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.tryParse(mainPlaylistUrl);
    if (uri == null) {
      return;
    }

    final segments = uri.pathSegments;
    final streamIndex = segments.lastIndexOf('stream');
    if (streamIndex < 0 || streamIndex >= segments.length - 1) {
      return;
    }

    final endUrl = uri.replace(
      pathSegments: [
        ...segments.take(streamIndex + 1),
        sessionId,
      ],
      query: null,
      fragment: null,
    );

    try {
      await _dio.delete<void>(
        endUrl.toString(),
        options: Options(
          headers: headers,
          extra: const {'skipRetry': true},
        ),
      );
    } catch (_) {
      // Session teardown is best-effort; the server expires abandoned ones.
    }
  }
}
