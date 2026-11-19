import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/config/demo_mode.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/immich_auth_method.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/core/models/saved_profile.dart';
import 'package:immichtv/src/core/models/saved_profile_secret.dart';
import 'package:immichtv/src/core/models/server_capabilities.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/repositories/server_capabilities_repository.dart';
import 'package:immichtv/src/platform/storage/profile_storage.dart';
import 'package:immichtv/src/features/auth/data/immich_auth_repository.dart';

void main() {
  test('saving a profile without a PIN marks it as unprotected', () async {
    final profileStorage = _InMemoryProfileStorage(
      profiles: const [],
      secrets: const {},
    );
    final repository = ImmichAuthRepository(
      dio: Dio(),
      profileStorage: profileStorage,
    );

    await repository.saveProfile(session: _session(), password: 'password');

    final profiles = await repository.getSavedProfiles();
    expect(profiles, hasLength(1));
    expect(profiles.single.pinEnabled, isFalse);
    final secret = await profileStorage.readProfileSecret(profiles.single.id);
    expect(secret?.pin, isNull);
    expect(secret?.password, 'password');
  });

  test('a profile without a PIN can be reopened without a PIN', () async {
    final profileStorage = _InMemoryProfileStorage(
      profiles: const [],
      secrets: const {},
    );
    final repository = ImmichAuthRepository(
      dio: Dio()..httpClientAdapter = _ThrowingHttpClientAdapter(),
      profileStorage: profileStorage,
    );

    await repository.saveProfile(
      session: _session(serverUrl: DemoMode.serverUrl),
      password: DemoMode.password,
    );

    final profiles = await repository.getSavedProfiles();
    final session = await repository.signInWithSavedProfile(
      profileId: profiles.single.id,
    );
    expect(session.user.email, DemoMode.email);
  });

  test('setProfilePin can enable and disable PIN protection', () async {
    final profileStorage = _InMemoryProfileStorage(
      profiles: const [],
      secrets: const {},
    );
    final repository = ImmichAuthRepository(
      dio: Dio(),
      profileStorage: profileStorage,
    );

    await repository.saveProfile(session: _session(), password: 'password');
    final profileId = (await repository.getSavedProfiles()).single.id;

    await repository.setProfilePin(
      profileId: profileId,
      enabled: true,
      pin: '4321',
    );
    var profile = (await repository.getSavedProfiles()).single;
    expect(profile.pinEnabled, isTrue);
    expect((await profileStorage.readProfileSecret(profileId))?.pin, '4321');

    await repository.setProfilePin(profileId: profileId, enabled: false);
    profile = (await repository.getSavedProfiles()).single;
    expect(profile.pinEnabled, isFalse);
    expect((await profileStorage.readProfileSecret(profileId))?.pin, isNull);
  });

  test(
    'saved demo profiles unlock through mock auth without remote login',
    () async {
      final profileStorage = _InMemoryProfileStorage(
        profiles: [
          SavedProfile(
            id: 'demo-profile',
            name: 'Demo User',
            email: DemoMode.email,
            serverConfig: ServerConfig(
              rawInput: DemoMode.serverUrl,
              serverUrl: Uri.parse(DemoMode.serverUrl),
              apiUrl: Uri.parse('${DemoMode.serverUrl}/api'),
            ),
            lastUsedAt: DateTime(2026),
          ),
        ],
        secrets: const {
          'demo-profile': SavedProfileSecret(
            password: DemoMode.password,
            pin: '1234',
          ),
        },
      );
      final dio = Dio()..httpClientAdapter = _ThrowingHttpClientAdapter();
      final repository = ImmichAuthRepository(
        dio: dio,
        profileStorage: profileStorage,
      );

      final session = await repository.signInWithSavedProfile(
        profileId: 'demo-profile',
        pin: '1234',
      );

      expect(session.user.email, DemoMode.email);
      expect(session.serverConfig.serverUrl.toString(), DemoMode.serverUrl);
      expect(session.accessToken, startsWith('mock-token-'));
    },
  );

  test('saved real profiles still use remote login', () async {
    final serverConfig = ServerConfig(
      rawInput: 'https://photos.example.com',
      serverUrl: Uri.parse('https://photos.example.com'),
      apiUrl: Uri.parse('https://photos.example.com/api'),
    );
    final profileStorage = _InMemoryProfileStorage(
      profiles: [
        SavedProfile(
          id: 'real-profile',
          name: 'Family Room',
          email: 'family@example.com',
          serverConfig: serverConfig,
          lastUsedAt: DateTime(2026),
        ),
      ],
      secrets: const {
        'real-profile': SavedProfileSecret(
          password: 'secret-password',
          pin: '1234',
        ),
      },
    );
    final dio = Dio()
      ..httpClientAdapter = _RecordingHttpClientAdapter(
        responses: {
          'POST https://photos.example.com/api/auth/login':
              ResponseBody.fromString(
                jsonEncode({'accessToken': 'remote-token'}),
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              ),
          'GET https://photos.example.com/api/users/me':
              ResponseBody.fromString(
                jsonEncode({
                  'id': 'remote-user',
                  'email': 'family@example.com',
                  'name': 'Family Room',
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              ),
        },
      );
    final repository = ImmichAuthRepository(
      dio: dio,
      profileStorage: profileStorage,
    );

    final session = await repository.signInWithSavedProfile(
      profileId: 'real-profile',
      pin: '1234',
    );

    expect(session.accessToken, 'remote-token');
    expect(session.user.email, 'family@example.com');
    expect(
      (dio.httpClientAdapter as _RecordingHttpClientAdapter).requests,
      containsAll(<String>[
        'POST https://photos.example.com/api/auth/login',
        'GET https://photos.example.com/api/users/me',
      ]),
    );
  });

  test('sign-in attaches discovered server capabilities to the session', () async {
    final capabilities = ServerCapabilities.fromProbe(
      version: const {'major': 3, 'minor': 3, 'patch': 0},
    );
    final repository = ImmichAuthRepository(
      dio: Dio()
        ..httpClientAdapter = _RecordingHttpClientAdapter(
          responses: {
            'GET https://photos.example.com/api/users/me':
                ResponseBody.fromString(
                  jsonEncode({
                    'id': 'api-user',
                    'email': 'apikey@example.com',
                    'name': 'API Living Room',
                  }),
                  200,
                  headers: {
                    Headers.contentTypeHeader: ['application/json'],
                  },
                ),
          },
        ),
      profileStorage: _InMemoryProfileStorage(
        profiles: const [],
        secrets: const {},
      ),
      capabilitiesRepository: _FakeCapabilitiesRepository(capabilities),
    );

    final session = await repository.signInWithApiKey(
      serverConfig: ServerConfig(
        rawInput: 'https://photos.example.com',
        serverUrl: Uri.parse('https://photos.example.com'),
        apiUrl: Uri.parse('https://photos.example.com/api'),
      ),
      apiKey: 'key',
    );

    expect(session.capabilities, capabilities);
  });

  test(
    'saved API key profiles re-authenticate through users/me only',
    () async {
      final serverConfig = ServerConfig(
        rawInput: 'https://photos.example.com',
        serverUrl: Uri.parse('https://photos.example.com'),
        apiUrl: Uri.parse('https://photos.example.com/api'),
      );
      final profileStorage = _InMemoryProfileStorage(
        profiles: [
          SavedProfile(
            id: 'api-profile',
            name: 'API Living Room',
            email: 'apikey@example.com',
            serverConfig: serverConfig,
            lastUsedAt: DateTime(2026),
            authMethod: ImmichAuthMethod.apiKey,
          ),
        ],
        secrets: const {
          'api-profile': SavedProfileSecret(
            apiKey: 'personal-api-key',
            pin: '1234',
          ),
        },
      );
      final dio = Dio()
        ..httpClientAdapter = _RecordingHttpClientAdapter(
          responses: {
            'GET https://photos.example.com/api/users/me':
                ResponseBody.fromString(
                  jsonEncode({
                    'id': 'api-user',
                    'email': 'apikey@example.com',
                    'name': 'API Living Room',
                  }),
                  200,
                  headers: {
                    Headers.contentTypeHeader: ['application/json'],
                  },
                ),
          },
        );
      final repository = ImmichAuthRepository(
        dio: dio,
        profileStorage: profileStorage,
      );

      final session = await repository.signInWithSavedProfile(
        profileId: 'api-profile',
        pin: '1234',
      );

      expect(session.accessToken, 'personal-api-key');
      expect(session.authMethod, ImmichAuthMethod.apiKey);
      expect(
        (dio.httpClientAdapter as _RecordingHttpClientAdapter).requests,
        equals(<String>['GET https://photos.example.com/api/users/me']),
      );
    },
  );
}

AuthenticatedSession _session({
  String serverUrl = 'https://photos.example.com',
  String email = DemoMode.email,
}) {
  final uri = Uri.parse(serverUrl);
  return AuthenticatedSession(
    serverConfig: ServerConfig(
      rawInput: serverUrl,
      serverUrl: uri,
      apiUrl: Uri.parse('$serverUrl/api'),
    ),
    accessToken: 'token',
    user: UserProfile(id: 'user-1', email: email, name: 'Owner'),
  );
}

class _FakeCapabilitiesRepository implements ServerCapabilitiesRepository {
  const _FakeCapabilitiesRepository(this._capabilities);

  final ServerCapabilities _capabilities;

  @override
  Future<ServerCapabilities> fetch(AuthenticatedSession session) async =>
      _capabilities;
}

class _InMemoryProfileStorage implements ProfileStorage {
  _InMemoryProfileStorage({
    required List<SavedProfile> profiles,
    required Map<String, SavedProfileSecret> secrets,
  }) : _profiles = List<SavedProfile>.from(profiles),
       _secrets = Map<String, SavedProfileSecret>.from(secrets);

  final List<SavedProfile> _profiles;
  final Map<String, SavedProfileSecret> _secrets;

  @override
  Future<List<SavedProfile>> readProfiles() async =>
      List<SavedProfile>.from(_profiles);

  @override
  Future<SavedProfileSecret?> readProfileSecret(String profileId) async =>
      _secrets[profileId];

  @override
  Future<void> saveProfile(SavedProfile profile) async {
    final index = _profiles.indexWhere((item) => item.id == profile.id);
    if (index >= 0) {
      _profiles[index] = profile;
      return;
    }
    _profiles.add(profile);
  }

  @override
  Future<void> saveProfileSecret({
    required String profileId,
    required SavedProfileSecret secret,
  }) async {
    _secrets[profileId] = secret;
  }
}

class _ThrowingHttpClientAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw StateError(
      'Unexpected network request: ${options.method} ${options.uri}',
    );
  }
}

class _RecordingHttpClientAdapter implements HttpClientAdapter {
  _RecordingHttpClientAdapter({required this.responses});

  final Map<String, ResponseBody> responses;
  final List<String> requests = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.uri}';
    requests.add(key);
    final response = responses[key];
    if (response == null) {
      throw StateError('No stubbed response for $key');
    }
    return response;
  }
}
