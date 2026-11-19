import 'package:equatable/equatable.dart';

/// Immich features that are not available on every server version or
/// configuration. Use [ServerCapabilities.supports] before calling their
/// endpoints so older servers keep working.
enum ServerFeature {
  memories,
  hlsVideo,
  map,
  people,
  ocr,
  smartSearch,
  randomAssets,
  calendarHeatmap,
  stacks,
  duplicates,
  tags,
  sharedPeople,
}

/// A snapshot of what the connected Immich server can do.
///
/// The probe is deliberately tolerant: [ServerCapabilities.unknown] is used
/// whenever version/config discovery fails, so the app falls back to the
/// conservative feature set instead of breaking sign-in.
class ServerCapabilities extends Equatable {
  const ServerCapabilities({
    this.major,
    this.minor,
    this.patch,
    this.featureLevel,
    this.mapEnabled,
    this.facialRecognitionEnabled,
    this.ocrEnabled,
    this.clipEnabled,
    this.duplicateDetectionEnabled,
    this.videoMimeTypes = const <String>[],
  });

  factory ServerCapabilities.unknown() => const ServerCapabilities();

  factory ServerCapabilities.demo() => const ServerCapabilities(
    major: 3,
    minor: 3,
    patch: 0,
    featureLevel: 1,
    mapEnabled: true,
    facialRecognitionEnabled: true,
    ocrEnabled: true,
    clipEnabled: true,
    duplicateDetectionEnabled: true,
    videoMimeTypes: <String>['video/mp4', 'video/quicktime', 'video/x-matroska'],
  );

  factory ServerCapabilities.fromProbe({
    Map<String, dynamic>? version,
    Map<String, dynamic>? mediaTypes,
    Map<String, dynamic>? userConfig,
  }) {
    final machineLearningEnabled = _nestedBool(
      userConfig,
      'machineLearning',
      'enabled',
    );

    bool? machineLearningFeature(String name) {
      if (machineLearningEnabled == false) {
        return false;
      }
      return _deepBool(userConfig, 'machineLearning', name, 'enabled');
    }

    return ServerCapabilities(
      major: _integer(version, 'major'),
      minor: _integer(version, 'minor'),
      patch: _integer(version, 'patch'),
      featureLevel: _integer(version, 'featureLevel'),
      mapEnabled: _nestedBool(userConfig, 'map', 'enabled'),
      facialRecognitionEnabled: machineLearningFeature('facialRecognition'),
      ocrEnabled: machineLearningFeature('ocr'),
      clipEnabled: machineLearningFeature('clip'),
      duplicateDetectionEnabled: machineLearningFeature('duplicateDetection'),
      videoMimeTypes: _stringList(mediaTypes, 'video'),
    );
  }

  final int? major;
  final int? minor;
  final int? patch;
  final int? featureLevel;
  final bool? mapEnabled;
  final bool? facialRecognitionEnabled;
  final bool? ocrEnabled;
  final bool? clipEnabled;
  final bool? duplicateDetectionEnabled;
  final List<String> videoMimeTypes;

  bool get isKnown => major != null;

  String get versionLabel {
    if (!isKnown) {
      return 'unknown';
    }
    return 'v$major.${minor ?? 0}.${patch ?? 0}';
  }

  bool supports(ServerFeature feature) {
    final detectedMajor = major;

    return switch (feature) {
      ServerFeature.memories =>
        detectedMajor == null || detectedMajor >= 2,
      ServerFeature.hlsVideo => _atLeast(3, 0),
      ServerFeature.map =>
        detectedMajor != null && (mapEnabled ?? false),
      ServerFeature.people => facialRecognitionEnabled ?? true,
      ServerFeature.ocr =>
        (detectedMajor == null || detectedMajor >= 2) &&
        (ocrEnabled ?? false),
      ServerFeature.smartSearch =>
        (detectedMajor == null || detectedMajor >= 2) &&
        (clipEnabled ?? true),
      ServerFeature.randomAssets =>
        detectedMajor == null || detectedMajor >= 2,
      ServerFeature.calendarHeatmap => _atLeast(3, 0),
      ServerFeature.stacks => detectedMajor == null || detectedMajor >= 2,
      ServerFeature.duplicates =>
        (detectedMajor == null || detectedMajor >= 2) &&
        (duplicateDetectionEnabled ?? true),
      ServerFeature.tags => detectedMajor == null || detectedMajor >= 2,
      ServerFeature.sharedPeople => _atLeast(3, 3),
    };
  }

  bool _atLeast(int targetMajor, int targetMinor) {
    final detectedMajor = major;
    if (detectedMajor == null) {
      return false;
    }
    if (detectedMajor != targetMajor) {
      return detectedMajor > targetMajor;
    }
    return (minor ?? 0) >= targetMinor;
  }

  Map<String, dynamic> toJson() {
    return {
      'major': major,
      'minor': minor,
      'patch': patch,
      'featureLevel': featureLevel,
      'mapEnabled': mapEnabled,
      'facialRecognitionEnabled': facialRecognitionEnabled,
      'ocrEnabled': ocrEnabled,
      'clipEnabled': clipEnabled,
      'duplicateDetectionEnabled': duplicateDetectionEnabled,
      'videoMimeTypes': videoMimeTypes,
    };
  }

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    return ServerCapabilities(
      major: json['major'] as int?,
      minor: json['minor'] as int?,
      patch: json['patch'] as int?,
      featureLevel: json['featureLevel'] as int?,
      mapEnabled: json['mapEnabled'] as bool?,
      facialRecognitionEnabled: json['facialRecognitionEnabled'] as bool?,
      ocrEnabled: json['ocrEnabled'] as bool?,
      clipEnabled: json['clipEnabled'] as bool?,
      duplicateDetectionEnabled: json['duplicateDetectionEnabled'] as bool?,
      videoMimeTypes:
          (json['videoMimeTypes'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
    );
  }

  static int? _integer(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static bool? _nestedBool(
    Map<String, dynamic>? map,
    String parent,
    String key,
  ) {
    final value = map?[parent];
    if (value is! Map) {
      return null;
    }
    final nested = value[key];
    return nested is bool ? nested : null;
  }

  static bool? _deepBool(
    Map<String, dynamic>? map,
    String parent,
    String child,
    String key,
  ) {
    final parentValue = map?[parent];
    if (parentValue is! Map) {
      return null;
    }
    final childValue = parentValue[child];
    if (childValue is! Map) {
      return null;
    }
    final value = childValue[key];
    return value is bool ? value : null;
  }

  static List<String> _stringList(Map<String, dynamic>? map, String key) {
    final value = map?[key];
    if (value is! List) {
      return const <String>[];
    }
    return value.whereType<String>().toList(growable: false);
  }

  @override
  List<Object?> get props => [
    major,
    minor,
    patch,
    featureLevel,
    mapEnabled,
    facialRecognitionEnabled,
    ocrEnabled,
    clipEnabled,
    duplicateDetectionEnabled,
    videoMimeTypes,
  ];
}
