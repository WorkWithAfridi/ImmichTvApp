import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/viewer/video_playback_policy.dart';
import 'package:video_player/video_player.dart';

void main() {
  test('uses the Immich transcode by default', () {
    final urls = resolvePlayableVideoUrls([
      'https://photos.example.com/api/assets/id/video/playback',
      'https://photos.example.com/api/assets/id/thumbnail?size=preview',
      'https://photos.example.com/api/assets/id/original',
      'https://cdn.example.com/fallback.mp4',
    ], hdrEnabled: false);

    expect(urls, [
      'https://photos.example.com/api/assets/id/video/playback',
      'https://cdn.example.com/fallback.mp4',
      'https://photos.example.com/api/assets/id/original',
    ]);
  });

  test('prefers the original video when HDR is enabled', () {
    final urls = resolvePlayableVideoUrls([
      'https://photos.example.com/api/assets/id/video/playback',
      'https://photos.example.com/api/assets/id/original',
      'https://cdn.example.com/fallback.mp4',
    ], hdrEnabled: true);

    expect(urls, [
      'https://photos.example.com/api/assets/id/original',
      'https://photos.example.com/api/assets/id/video/playback',
      'https://cdn.example.com/fallback.mp4',
    ]);
  });

  test('only uses the SurfaceView-backed Android player for HDR', () {
    expect(
      nativeVideoViewType(TargetPlatform.android, hdrEnabled: false),
      VideoViewType.textureView,
    );
    expect(
      nativeVideoViewType(TargetPlatform.android, hdrEnabled: true),
      VideoViewType.platformView,
    );
    expect(
      nativeVideoViewType(TargetPlatform.windows, hdrEnabled: true),
      VideoViewType.textureView,
    );
  });
}
