import '../../../core/models/asset_detail.dart';
import '../../../core/models/authenticated_session.dart';
import '../../../core/repositories/asset_detail_repository.dart';

class MockAssetDetailRepository implements AssetDetailRepository {
  const MockAssetDetailRepository();

  @override
  Future<AssetDetail?> fetchDetail(
    AuthenticatedSession session,
    String assetId,
  ) async {
    return AssetDetail(
      id: assetId,
      description: 'A highlight from your demo library.',
      make: 'Immich',
      model: 'Demo Camera',
      originalFileName: 'IMG_$assetId.jpg',
      takenAt: DateTime.utc(2025, 6, 1),
      city: 'Lisbon',
      country: 'Portugal',
      metadata: const {'Source': 'Demo library'},
      ocrTexts: const <String>[],
    );
  }
}
