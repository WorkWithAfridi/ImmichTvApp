import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/immich_auth_method.dart';
import 'package:immichtv/src/core/models/server_capabilities.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';

void main() {
  group('fromProbe', () {
    test('reads version, media types, and user config flags', () {
      final capabilities = ServerCapabilities.fromProbe(
        version: const {
          'major': 3,
          'minor': 2,
          'patch': 1,
          'featureLevel': 7,
        },
        mediaTypes: const {'video': ['video/mp4', 'video/quicktime']},
        userConfig: const {
          'map': {'enabled': true},
          'machineLearning': {
            'enabled': true,
            'facialRecognition': {'enabled': true},
            'ocr': {'enabled': false},
            'clip': {'enabled': true},
            'duplicateDetection': {'enabled': true},
          },
        },
      );

      expect(capabilities.versionLabel, 'v3.2.1');
      expect(capabilities.featureLevel, 7);
      expect(capabilities.videoMimeTypes, ['video/mp4', 'video/quicktime']);
      expect(capabilities.supports(ServerFeature.map), isTrue);
      expect(capabilities.supports(ServerFeature.people), isTrue);
      expect(capabilities.supports(ServerFeature.ocr), isFalse);
      expect(capabilities.supports(ServerFeature.smartSearch), isTrue);
    });

    test('disables all machine learning features when ML is off', () {
      final capabilities = ServerCapabilities.fromProbe(
        version: const {'major': 3, 'minor': 3, 'patch': 0},
        userConfig: const {
          'machineLearning': {
            'enabled': false,
            'facialRecognition': {'enabled': true},
            'ocr': {'enabled': true},
            'clip': {'enabled': true},
          },
        },
      );

      expect(capabilities.supports(ServerFeature.people), isFalse);
      expect(capabilities.supports(ServerFeature.ocr), isFalse);
      expect(capabilities.supports(ServerFeature.smartSearch), isFalse);
    });
  });

  group('supports', () {
    test('unknown servers keep the current feature set but gate newer APIs', () {
      final capabilities = ServerCapabilities.unknown();

      expect(capabilities.isKnown, isFalse);
      expect(capabilities.supports(ServerFeature.people), isTrue);
      expect(capabilities.supports(ServerFeature.memories), isTrue);
      expect(capabilities.supports(ServerFeature.tags), isTrue);
      expect(capabilities.supports(ServerFeature.map), isFalse);
      expect(capabilities.supports(ServerFeature.hlsVideo), isFalse);
      expect(capabilities.supports(ServerFeature.calendarHeatmap), isFalse);
      expect(capabilities.supports(ServerFeature.sharedPeople), isFalse);
    });

    test('gates HLS and calendar APIs on v3 and shared people on v3.3', () {
      const v3_0 = ServerCapabilities(major: 3, minor: 0, patch: 0);
      const v3_2 = ServerCapabilities(major: 3, minor: 2, patch: 0);
      const v3_3 = ServerCapabilities(major: 3, minor: 3, patch: 0);

      expect(v3_0.supports(ServerFeature.hlsVideo), isTrue);
      expect(v3_0.supports(ServerFeature.calendarHeatmap), isTrue);
      expect(v3_2.supports(ServerFeature.sharedPeople), isFalse);
      expect(v3_3.supports(ServerFeature.sharedPeople), isTrue);
    });

    test('map requires both a known version and the feature flag', () {
      const disabled = ServerCapabilities(major: 3, mapEnabled: false);
      const enabled = ServerCapabilities(major: 3, mapEnabled: true);

      expect(disabled.supports(ServerFeature.map), isFalse);
      expect(enabled.supports(ServerFeature.map), isTrue);
    });
  });

  test('survives a JSON round trip', () {
    final original = ServerCapabilities.fromProbe(
      version: const {'major': 3, 'minor': 3, 'patch': 0},
      mediaTypes: const {'video': ['video/mp4']},
      userConfig: const {
        'map': {'enabled': true},
      },
    );

    expect(ServerCapabilities.fromJson(original.toJson()), original);
  });

  test('session JSON written by older builds still loads', () {
    final session = AuthenticatedSession(
      serverConfig: ServerConfig(
        rawInput: 'https://photos.example.com',
        serverUrl: Uri.parse('https://photos.example.com'),
        apiUrl: Uri.parse('https://photos.example.com/api'),
      ),
      accessToken: 'token',
      user: const UserProfile(id: 'id', email: 'user@example.com', name: 'User'),
      authMethod: ImmichAuthMethod.apiKey,
    );

    final decoded = AuthenticatedSession.fromJson(session.toJson());

    expect(decoded.capabilities.isKnown, isFalse);
  });
}
