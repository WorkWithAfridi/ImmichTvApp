import 'package:equatable/equatable.dart';

class AssetSummary extends Equatable {
  const AssetSummary({
    required this.id,
    required this.thumbnailUrls,
    required this.displayUrls,
    required this.type,
    required this.createdAt,
    this.requiresAuth = true,
    this.hlsUrl,
  });

  final String id;
  final List<String> thumbnailUrls;
  final List<String> displayUrls;
  final String type;
  final DateTime createdAt;
  final bool requiresAuth;

  /// Alpha Immich HLS playlist URL for videos. Present only when the connected
  /// server supports adaptive streaming; the viewer falls back to the regular
  /// playback URLs if it fails.
  final String? hlsUrl;

  bool get isVideo => type.toUpperCase().contains('VIDEO');

  String get thumbnailUrl => thumbnailUrls.first;

  String get displayUrl => displayUrls.first;

  @override
  List<Object?> get props => [
    id,
    thumbnailUrls,
    displayUrls,
    type,
    createdAt,
    requiresAuth,
    hlsUrl,
  ];
}
