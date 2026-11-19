import '../models/album_summary.dart';
import '../models/asset_sort_order.dart';
import '../models/authenticated_session.dart';
import '../models/asset_summary.dart';
import '../models/media_page.dart';
import '../models/memory_summary.dart';
import '../models/person_summary.dart';

abstract class MediaRepository {
  Future<List<AlbumSummary>> fetchAlbums(AuthenticatedSession session);

  Future<List<PersonSummary>> fetchPeople(AuthenticatedSession session);

  /// Returns memories when the connected server supports them, otherwise an
  /// empty list. Callers should gate on `ServerFeature.memories`.
  Future<List<MemorySummary>> fetchMemories(AuthenticatedSession session);

  Future<MediaPage<AssetSummary>> fetchAlbumAssetsPage(
    AuthenticatedSession session, {
    required String albumId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  });

  Future<MediaPage<AssetSummary>> fetchPersonAssetsPage(
    AuthenticatedSession session, {
    required String personId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  });

  Future<MediaPage<AssetSummary>> fetchTimelinePage(
    AuthenticatedSession session, {
    String? page,
    int pageSize = 30,
    int? year,
  });

  Future<MediaPage<AssetSummary>> fetchFavoritesPage(
    AuthenticatedSession session, {
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 30,
  });
}
