import '../models/asset_detail.dart';
import '../models/authenticated_session.dart';

abstract class AssetDetailRepository {
  /// Returns null when the asset is unavailable or the server does not
  /// expose detail endpoints. The viewer keeps working without an info panel.
  Future<AssetDetail?> fetchDetail(
    AuthenticatedSession session,
    String assetId,
  );
}
