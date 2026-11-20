import 'package:equatable/equatable.dart';

/// Read-only detail data shown in the viewer's info panel.
class AssetDetail extends Equatable {
  const AssetDetail({
    required this.id,
    this.description = '',
    this.make = '',
    this.model = '',
    this.originalFileName = '',
    this.takenAt,
    this.city = '',
    this.state = '',
    this.country = '',
    this.metadata = const <String, String>{},
    this.ocrTexts = const <String>[],
  });

  factory AssetDetail.fromJson(
    Map<String, dynamic> asset, {
    Map<String, String> metadata = const <String, String>{},
    List<String> ocrTexts = const <String>[],
  }) {
    final exif = asset['exifInfo'];
    final exifMap = exif is Map ? Map<String, dynamic>.from(exif) : null;
    final takenAt = DateTime.tryParse(
      (exifMap?['dateTimeOriginal'] ?? asset['fileCreatedAt'])?.toString() ?? '',
    );

    String field(String key) {
      final value = exifMap?[key] ?? asset[key];
      return value?.toString().trim() ?? '';
    }

    return AssetDetail(
      id: (asset['id']?.toString() ?? ''),
      description: field('description'),
      make: field('make'),
      model: field('model'),
      originalFileName: field('originalFileName'),
      takenAt: takenAt,
      city: field('city'),
      state: field('state'),
      country: field('country'),
      metadata: metadata,
      ocrTexts: List<String>.unmodifiable(
        ocrTexts.where((text) => text.trim().isNotEmpty),
      ),
    );
  }

  final String id;
  final String description;
  final String make;
  final String model;
  final String originalFileName;
  final DateTime? takenAt;
  final String city;
  final String state;
  final String country;
  final Map<String, String> metadata;
  final List<String> ocrTexts;

  String get location {
    final parts = <String>[
      if (city.isNotEmpty) city,
      if (state.isNotEmpty && state != city) state,
      if (country.isNotEmpty) country,
    ];
    return parts.join(', ');
  }

  String get camera => [make, model].where((part) => part.isNotEmpty).join(' ').trim();

  @override
  List<Object?> get props => [
    id,
    description,
    make,
    model,
    originalFileName,
    takenAt,
    city,
    state,
    country,
    metadata,
    ocrTexts,
  ];
}
