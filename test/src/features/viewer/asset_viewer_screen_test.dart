import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/core/models/immich_auth_method.dart';
import 'package:immichtv/src/core/repositories/asset_image_repository.dart';
import 'package:immichtv/src/features/viewer/asset_viewer_screen.dart';
import 'package:immichtv/src/features/viewer/hdr_playback_preference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HDR control toggles and saves the viewer playback mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final preference = _MemoryHdrPlaybackPreference(false);
    await _pumpViewer(tester, preference);

    expect(find.text('HDR'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hdr-playback-disabled-slash')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Enable HDR playback'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    for (var index = 0; index < 5; index += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('HDR'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hdr-playback-disabled-slash')),
      findsNothing,
    );
    expect(preference.enabled, isTrue);
  });

  testWidgets('HDR control restores the saved mode and can disable it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final preference = _MemoryHdrPlaybackPreference(true);
    await _pumpViewer(tester, preference);

    expect(find.text('HDR'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hdr-playback-disabled-slash')),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Disable HDR playback'), findsOneWidget);

    await tester.tap(find.text('HDR'));
    await tester.pump();

    expect(find.text('HDR'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hdr-playback-disabled-slash')),
      findsOneWidget,
    );
    expect(preference.enabled, isFalse);
  });
}

Future<void> _pumpViewer(
  WidgetTester tester,
  HdrPlaybackPreference preference,
) async {
  await tester.pumpWidget(
    RepositoryProvider<AssetImageRepository>.value(
      value: _FakeAssetImageRepository(),
      child: MaterialApp(
        home: AssetViewerScreen(
          assets: [_videoAsset],
          initialIndex: 0,
          accessToken: 'test-token',
          hdrPlaybackPreference: preference,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final _videoAsset = AssetSummary(
  id: 'video-1',
  thumbnailUrls: const ['mock://video-1?variant=thumbnail'],
  displayUrls: const [
    'https://photos.example.com/api/assets/video-1/original',
    'https://photos.example.com/api/assets/video-1/video/playback',
  ],
  type: 'VIDEO',
  createdAt: DateTime(2026, 8, 8),
);

class _MemoryHdrPlaybackPreference extends HdrPlaybackPreference {
  _MemoryHdrPlaybackPreference(this.enabled);

  bool enabled;

  @override
  Future<bool> load() async => enabled;

  @override
  Future<void> save(bool enabled) async {
    this.enabled = enabled;
  }
}

class _FakeAssetImageRepository implements AssetImageRepository {
  @override
  Future<void> prefetchImages({
    required List<List<String>> urls,
    required String accessToken,
    required ImmichAuthMethod authMethod,
  }) async {}
}
