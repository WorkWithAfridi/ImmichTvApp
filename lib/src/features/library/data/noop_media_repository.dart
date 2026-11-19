import '../../../core/models/album_summary.dart';
import '../../../core/models/asset_sort_order.dart';
import '../../../core/models/authenticated_session.dart';
import '../../../core/models/asset_summary.dart';
import '../../../core/models/media_page.dart';
import '../../../core/models/memory_summary.dart';
import '../../../core/models/person_summary.dart';
import '../../../core/repositories/media_repository.dart';

class NoopMediaRepository implements MediaRepository {
  @override
  Future<List<AlbumSummary>> fetchAlbums(AuthenticatedSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return const [];
  }

  @override
  Future<List<PersonSummary>> fetchPeople(AuthenticatedSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return const [];
  }

  @override
  Future<List<MemorySummary>> fetchMemories(AuthenticatedSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return const [];
  }

  @override
  Future<MediaPage<AssetSummary>> fetchAlbumAssetsPage(
    AuthenticatedSession session, {
    required String albumId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return const MediaPage(items: []);
  }

  @override
  Future<MediaPage<AssetSummary>> fetchFavoritesPage(
    AuthenticatedSession session, {
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 60,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return const MediaPage(items: []);
  }

  @override
  Future<MediaPage<AssetSummary>> fetchPersonAssetsPage(
    AuthenticatedSession session, {
    required String personId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return const MediaPage(items: []);
  }

  @override
  Future<MediaPage<AssetSummary>> fetchTimelinePage(
    AuthenticatedSession session, {
    String? page,
    int pageSize = 60,
    int? year,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return const MediaPage(items: []);
  }
}
