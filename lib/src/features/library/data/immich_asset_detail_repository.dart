import 'package:dio/dio.dart';

import '../../../core/config/demo_mode.dart';
import '../../../core/models/asset_detail.dart';
import '../../../core/models/authenticated_session.dart';
import '../../../core/models/server_capabilities.dart';
import '../../../core/network/immich_headers.dart';
import '../../../core/repositories/asset_detail_repository.dart';
import '../../mock/data/mock_asset_detail_repository.dart';

class ImmichAssetDetailRepository implements AssetDetailRepository {
  ImmichAssetDetailRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<AssetDetail?> fetchDetail(
    AuthenticatedSession session,
    String assetId,
  ) async {
    if (DemoMode.matchesServerUrl(session.serverConfig.serverUrl)) {
      return MockAssetDetailRepository().fetchDetail(session, assetId);
    }

    final headers = ImmichHeaders.sessionHeaders(session);
    try {
      final response = await _dio.get<dynamic>(
        session.serverConfig.apiEndpoint('assets/$assetId').toString(),
        options: Options(headers: headers),
      );
      final data = response.data;
      if (data is! Map) {
        return null;
      }
      final asset = Map<String, dynamic>.from(data);

      final metadata = await _fetchMetadata(session, assetId, headers);
      final ocr = session.capabilities.supports(ServerFeature.ocr)
          ? await _fetchOcr(session, assetId, headers)
          : const <String>[];

      return AssetDetail.fromJson(
        asset,
        metadata: metadata,
        ocrTexts: ocr,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _fetchMetadata(
    AuthenticatedSession session,
    String assetId,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _dio.get<dynamic>(
        session.serverConfig
            .apiEndpoint('assets/$assetId/metadata')
            .toString(),
        options: Options(headers: headers),
      );
      final data = response.data;
      if (data is! List) {
        return const <String, String>{};
      }
      final result = <String, String>{};
      for (final item in data) {
        if (item is! Map) {
          continue;
        }
        final key = item['key']?.toString();
        if (key == null || key.isEmpty) {
          continue;
        }
        final value = item['value'];
        result[key] = value is Map
            ? (value['value'] ?? value.toString()).toString()
            : value?.toString() ?? '';
      }
      return result;
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<List<String>> _fetchOcr(
    AuthenticatedSession session,
    String assetId,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _dio.get<dynamic>(
        session.serverConfig.apiEndpoint('assets/$assetId/ocr').toString(),
        options: Options(headers: headers),
      );
      final data = response.data;
      if (data is! List) {
        return const <String>[];
      }
      return data
          .whereType<Map>()
          .map((item) => item['text']?.toString().trim() ?? '')
          .where((text) => text.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }
}
