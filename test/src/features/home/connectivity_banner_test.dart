import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/album_summary.dart';
import 'package:immichtv/src/core/models/asset_sort_order.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/immich_auth_method.dart';
import 'package:immichtv/src/core/models/media_page.dart';
import 'package:immichtv/src/core/models/memory_summary.dart';
import 'package:immichtv/src/core/models/person_summary.dart';
import 'package:immichtv/src/core/models/saved_profile.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/core/repositories/asset_image_repository.dart';
import 'package:immichtv/src/core/repositories/auth_repository.dart';
import 'package:immichtv/src/core/repositories/media_repository.dart';
import 'package:immichtv/src/features/home/home_screen.dart';

void main() {
  testWidgets('shows an offline banner that can retry a failed refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final media = _FakeMediaRepository()..failAlbums = true;
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<MediaRepository>.value(value: media),
          RepositoryProvider<AssetImageRepository>.value(
            value: _NoopAssetImageRepository(),
          ),
          RepositoryProvider<AuthRepository>.value(
            value: _NoopAuthRepository(),
          ),
        ],
        child: MaterialApp(home: HomeScreen(session: _session())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline — showing cached photos'), findsOneWidget);
    expect(find.textContaining('Last updated'), findsOneWidget);

    media.failAlbums = false;
    await tester.tap(find.text('Offline — showing cached photos'));
    await tester.pumpAndSettle();

    expect(find.text('Offline — showing cached photos'), findsNothing);
  });
}

class _FakeMediaRepository implements MediaRepository {
  bool failAlbums = false;

  @override
  Future<List<AlbumSummary>> fetchAlbums(AuthenticatedSession session) async {
    if (failAlbums) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/albums'),
        reason: 'connection refused',
      );
    }
    return const [AlbumSummary(id: 'a', name: 'Album', assetCount: 1)];
  }

  @override
  Future<List<MemorySummary>> fetchMemories(AuthenticatedSession session) async =>
      const <MemorySummary>[];

  @override
  Future<List<PersonSummary>> fetchPeople(AuthenticatedSession session) async =>
      const [];

  @override
  Future<MediaPage<AssetSummary>> fetchAlbumAssetsPage(
    AuthenticatedSession session, {
    required String albumId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => const MediaPage(items: []);

  @override
  Future<MediaPage<AssetSummary>> fetchPersonAssetsPage(
    AuthenticatedSession session, {
    required String personId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => const MediaPage(items: []);

  @override
  Future<MediaPage<AssetSummary>> fetchTimelinePage(
    AuthenticatedSession session, {
    String? page,
    int pageSize = 30,
    int? year,
  }) async => const MediaPage(items: []);

  @override
  Future<MediaPage<AssetSummary>> fetchFavoritesPage(
    AuthenticatedSession session, {
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 30,
  }) async => const MediaPage(items: []);
}

class _NoopAssetImageRepository implements AssetImageRepository {
  @override
  Future<void> prefetchImages({
    required List<List<String>> urls,
    required String accessToken,
    required ImmichAuthMethod authMethod,
  }) async {}
}

class _NoopAuthRepository implements AuthRepository {
  @override
  Future<AuthenticatedSession> signIn({
    required ServerConfig serverConfig,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthenticatedSession> signInWithApiKey({
    required ServerConfig serverConfig,
    required String apiKey,
  }) => throw UnimplementedError();

  @override
  Future<List<SavedProfile>> getSavedProfiles() async => const [];

  @override
  Future<void> saveProfile({
    required AuthenticatedSession session,
    String? password,
    String? apiKey,
    String? pin,
  }) async {}

  @override
  Future<AuthenticatedSession> signInWithSavedProfile({
    required String profileId,
    String? pin,
  }) => throw UnimplementedError();

  @override
  Future<void> setProfilePin({
    required String profileId,
    required bool enabled,
    String? pin,
  }) async {}

  @override
  Future<void> signOut() async {}
}

AuthenticatedSession _session() {
  return AuthenticatedSession(
    serverConfig: ServerConfig(
      rawInput: 'https://photos.example.com',
      serverUrl: Uri.parse('https://photos.example.com'),
      apiUrl: Uri.parse('https://photos.example.com/api'),
    ),
    accessToken: 'token',
    user: const UserProfile(id: 'user', email: 'user@example.com', name: 'TV'),
  );
}
