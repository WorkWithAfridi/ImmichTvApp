import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/features/slideshow/slideshow_page_loader.dart';
import 'package:immichtv/src/features/slideshow/slideshow_player_screen.dart';

void main() {
  testWidgets('loads another page and keeps advancing past the last asset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var loaderCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SlideshowPlayerScreen(
          assets: [_asset('a1', DateTime.utc(2026, 1, 1))],
          accessToken: 'token',
          initialDurationSeconds: 1,
          hasMorePages: true,
          prefetchThreshold: 1,
          pageLoader: () async {
            loaderCalls++;
            return SlideshowPage(
              items: [_AssetForTest.a2, _AssetForTest.a3],
              hasMore: false,
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2026-01-01'), findsOneWidget);

    // Timer fires, the source is exhausted, so the next page is requested.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    expect(loaderCalls, 1);
    expect(find.text('2025-02-02'), findsOneWidget);

    // The slideshow continues into the newly loaded page instead of wrapping.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('2024-03-03'), findsOneWidget);
  });

  testWidgets('wraps around only when there are no more pages', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: SlideshowPlayerScreen(
          assets: [
            _asset('a1', DateTime.utc(2026, 1, 1)),
            _asset('a2', DateTime.utc(2025, 2, 2)),
          ],
          accessToken: 'token',
          initialDurationSeconds: 1,
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2025-02-02'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2026-01-01'), findsOneWidget);
  });
}

class _AssetForTest {
  static final a2 = _asset('a2', DateTime.utc(2025, 2, 2));
  static final a3 = _asset('a3', DateTime.utc(2024, 3, 3));
}

AssetSummary _asset(String id, DateTime createdAt) {
  return AssetSummary(
    id: id,
    thumbnailUrls: ['https://example.test/$id/thumb'],
    displayUrls: ['https://example.test/$id/full'],
    type: 'IMAGE',
    createdAt: createdAt,
  );
}
