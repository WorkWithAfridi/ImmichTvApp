import 'package:equatable/equatable.dart';

import 'asset_summary.dart';

/// A city with photos, derived from Immich's "one asset per city" endpoint.
class PlaceSummary extends Equatable {
  const PlaceSummary({
    required this.id,
    required this.city,
    required this.state,
    required this.country,
    required this.preview,
  });

  factory PlaceSummary.fromAsset(AssetSummary asset) {
    final city = asset.city?.trim() ?? '';
    final state = asset.state?.trim() ?? '';
    final country = asset.country?.trim() ?? '';
    final label = city.isNotEmpty ? city : (state.isNotEmpty ? state : country);
    final key = '$label|$country';

    return PlaceSummary(
      id: key,
      city: label,
      state: state,
      country: country,
      preview: asset,
    );
  }

  final String id;
  final String city;
  final String state;
  final String country;
  final AssetSummary preview;

  String get subtitle {
    final parts = <String>[
      if (state.isNotEmpty && state != city) state,
      if (country.isNotEmpty && country != state) country,
    ];
    return parts.join(', ');
  }

  @override
  List<Object?> get props => [id, city, state, country, preview];
}
