import 'package:equatable/equatable.dart';

import 'asset_summary.dart';

/// A read-only Immich memory ("On this day", birthday, etc.) with the assets
/// already resolved so the viewer can open it without a second request.
class MemorySummary extends Equatable {
  const MemorySummary({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.memoryAt,
    required this.assets,
    this.type = '',
  });

  factory MemorySummary.fromJson(
    Map<String, dynamic> json, {
    required List<AssetSummary> assets,
    DateTime? now,
  }) {
    final id = json['id'] as String? ?? '';
    final data = json['data'];
    final dataMap = data is Map ? Map<String, dynamic>.from(data) : null;
    final personName = dataMap?['personName']?.toString().trim();
    final year = dataMap?['year'];
    final memoryAt = DateTime.tryParse(json['memoryAt']?.toString() ?? '');
    final type = json['type']?.toString() ?? '';
    final today = now ?? DateTime.now();

    final title = (personName != null && personName.isNotEmpty)
        ? '$personName\'s birthday'
        : (year != null ? '$year' : 'On this day');

    final yearsAgo = memoryAt == null ? null : today.year - memoryAt.year;
    final subtitle = switch (yearsAgo) {
      final int value when value > 1 => '$value years ago',
      1 => 'One year ago',
      0 => 'This year',
      _ => 'A moment to remember',
    };

    return MemorySummary(
      id: id,
      title: title,
      subtitle: subtitle,
      memoryAt: memoryAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      assets: List<AssetSummary>.unmodifiable(assets),
      type: type,
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final DateTime memoryAt;
  final List<AssetSummary> assets;
  final String type;

  bool get isBirthday => type.toUpperCase().contains('BIRTHDAY');

  @override
  List<Object?> get props => [id, title, subtitle, memoryAt, assets, type];
}
