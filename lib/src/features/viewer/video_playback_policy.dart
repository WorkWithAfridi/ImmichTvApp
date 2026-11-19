import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

VideoViewType nativeVideoViewType(
  TargetPlatform platform, {
  required bool hdrEnabled,
}) {
  return platform == TargetPlatform.android && hdrEnabled
      ? VideoViewType.platformView
      : VideoViewType.textureView;
}

List<String> resolvePlayableVideoUrls(
  Iterable<String> displayUrls, {
  required bool hdrEnabled,
  bool preferHls = false,
}) {
  final originalUrls = <String>[];
  final playbackUrls = <String>[];
  final directMediaUrls = <String>[];
  final hlsUrls = <String>[];

  for (final url in displayUrls) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      continue;
    }

    final uri = Uri.tryParse(trimmed);
    final path = uri?.path.toLowerCase() ?? trimmed.toLowerCase();
    if (path.endsWith('.m3u8')) {
      hlsUrls.add(trimmed);
      continue;
    }
    if (path.contains('/original')) {
      originalUrls.add(trimmed);
      continue;
    }
    if (path.contains('/video/playback')) {
      playbackUrls.add(trimmed);
      continue;
    }
    if (path.endsWith('.mp4') ||
        path.endsWith('.webm') ||
        path.endsWith('.mov')) {
      directMediaUrls.add(trimmed);
    }
  }

  if (preferHls && hlsUrls.isNotEmpty) {
    return <String>[
      ...hlsUrls,
      ...playbackUrls,
      ...directMediaUrls,
      ...originalUrls,
    ];
  }

  if (hdrEnabled) {
    return <String>[
      ...originalUrls,
      ...playbackUrls,
      ...directMediaUrls,
      ...hlsUrls,
    ];
  }

  return <String>[
    ...playbackUrls,
    ...directMediaUrls,
    ...originalUrls,
    ...hlsUrls,
  ];
}
