import 'package:dio/dio.dart';

import '../../../core/config/demo_mode.dart';
import '../../../core/models/authenticated_session.dart';
import '../../../core/models/server_capabilities.dart';
import '../../../core/network/immich_headers.dart';
import '../../../core/repositories/server_capabilities_repository.dart';

class ImmichServerCapabilitiesRepository
    implements ServerCapabilitiesRepository {
  ImmichServerCapabilitiesRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<ServerCapabilities> fetch(AuthenticatedSession session) async {
    if (DemoMode.matchesServerUrl(session.serverConfig.serverUrl)) {
      return ServerCapabilities.demo();
    }

    final headers = ImmichHeaders.sessionHeaders(session);
    final responses = await Future.wait<Object?>([
      _fetchMap(session, 'server/version', headers),
      _fetchMap(session, 'server/media-types', headers),
      _fetchMap(session, 'config', headers),
    ]);

    return ServerCapabilities.fromProbe(
      version: responses[0] as Map<String, dynamic>?,
      mediaTypes: responses[1] as Map<String, dynamic>?,
      userConfig: responses[2] as Map<String, dynamic>?,
    );
  }

  Future<Map<String, dynamic>?> _fetchMap(
    AuthenticatedSession session,
    String path,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _dio.get<dynamic>(
        session.serverConfig.apiEndpoint(path).toString(),
        // Capability discovery is best-effort; retrying here would only add
        // latency to sign-in when a probe endpoint is missing or throttled.
        options: Options(headers: headers, extra: const {'skipRetry': true}),
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (_) {
      // One missing or forbidden probe must not disable the others.
      return null;
    }
  }
}
