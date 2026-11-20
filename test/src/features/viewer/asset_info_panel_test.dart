import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/asset_detail.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/immich_auth_method.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/core/repositories/asset_detail_repository.dart';
import 'package:immichtv/src/core/repositories/asset_image_repository.dart';
import 'package:immichtv/src/features/viewer/asset_viewer_screen.dart';

void main() {
  testWidgets('pressing I opens the asset info panel with EXIF and OCR', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final detail = AssetDetail(
      id: 'asset-1',
      description: 'Sunset over the river',
      make: 'Canon',
      model: 'EOS R6',
      originalFileName: 'IMG_1234.jpg',
      takenAt: DateTime.utc(2025, 6, 1),
      city: 'Lisbon',
      country: 'Portugal',
      metadata: const {'Rating': '5'},
      ocrTexts: const ['WELCOME'],
    );

    await tester.pumpWidget(
      RepositoryProvider<AssetImageRepository>.value(
        value: _NoopAssetImageRepository(),
        child: MaterialApp(
          home: AssetViewerScreen(
            assets: [_asset],
            initialIndex: 0,
            accessToken: 'token',
            session: _session(),
            assetDetailRepository: _FakeDetailRepository(detail),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Asset info'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    await tester.pump();

    expect(find.text('Asset info'), findsOneWidget);
    expect(find.text('Sunset over the river'), findsOneWidget);
    expect(find.text('Canon EOS R6'), findsOneWidget);
    expect(find.text('Lisbon, Portugal'), findsOneWidget);
    expect(find.text('WELCOME'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    expect(find.text('Asset info'), findsNothing);
  });
}

final _asset = AssetSummary(
  id: 'asset-1',
  thumbnailUrls: const ['mock://asset-1?variant=thumbnail'],
  displayUrls: const ['mock://asset-1?variant=display'],
  type: 'IMAGE',
  createdAt: DateTime.utc(2025, 6, 1),
);

AuthenticatedSession _session() {
  return AuthenticatedSession(
    serverConfig: ServerConfig(
      rawInput: 'https://photos.example.com',
      serverUrl: Uri.parse('https://photos.example.com'),
      apiUrl: Uri.parse('https://photos.example.com/api'),
    ),
    accessToken: 'token',
    user: const UserProfile(id: 'user', email: 'user@example.com', name: 'TV'),
    authMethod: ImmichAuthMethod.apiKey,
  );
}

class _FakeDetailRepository implements AssetDetailRepository {
  const _FakeDetailRepository(this.detail);

  final AssetDetail detail;

  @override
  Future<AssetDetail?> fetchDetail(
    AuthenticatedSession session,
    String assetId,
  ) async => detail;
}

class _NoopAssetImageRepository implements AssetImageRepository {
  @override
  Future<void> prefetchImages({
    required List<List<String>> urls,
    required String accessToken,
    required ImmichAuthMethod authMethod,
  }) async {}
}
