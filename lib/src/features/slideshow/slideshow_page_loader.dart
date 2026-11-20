import '../../core/models/asset_summary.dart';

/// One page of assets for a running slideshow.
class SlideshowPage {
  const SlideshowPage({
    required this.items,
    this.hasMore = false,
  });

  final List<AssetSummary> items;
  final bool hasMore;
}

/// Supplied by the tab that launched the viewer. Returns the next page from
/// whatever source the slideshow is playing (timeline, album, person, etc.).
typedef SlideshowPageLoader = Future<SlideshowPage> Function();
