import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/saved_profile.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/core/repositories/auth_repository.dart';
import 'package:immichtv/src/features/settings/cubit/settings_cubit.dart';

void main() {
  test('load resolves the current saved profile and its PIN state', () async {
    final repository = _FakeAuthRepository(
      profile: _savedProfile(pinEnabled: true),
    );
    final cubit = SettingsCubit(
      authRepository: repository,
      session: _session(),
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.isLoaded, isTrue);
    expect(cubit.state.profileId, 'profile-1');
    expect(cubit.state.pinEnabled, isTrue);
  });

  test('setPinEnabled updates the repository and the cubit state', () async {
    final repository = _FakeAuthRepository(
      profile: _savedProfile(pinEnabled: false),
    );
    final cubit = SettingsCubit(
      authRepository: repository,
      session: _session(),
    );
    addTearDown(cubit.close);
    await cubit.load();

    final enabled = await cubit.setPinEnabled(true, pin: '2580');
    expect(enabled, isTrue);
    expect(cubit.state.pinEnabled, isTrue);
    expect(repository.lastPin, '2580');
    expect(repository.lastEnabled, isTrue);

    final disabled = await cubit.setPinEnabled(false);
    expect(disabled, isTrue);
    expect(cubit.state.pinEnabled, isFalse);
    expect(repository.lastEnabled, isFalse);
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required this.profile});

  SavedProfile profile;
  bool? lastEnabled;
  String? lastPin;

  @override
  Future<List<SavedProfile>> getSavedProfiles() async => [profile];

  @override
  Future<void> saveProfile({
    required AuthenticatedSession session,
    String? password,
    String? apiKey,
    String? pin,
  }) async {}

  @override
  Future<AuthenticatedSession> signIn({
    required ServerConfig serverConfig,
    required String email,
    required String password,
  }) async => _session();

  @override
  Future<AuthenticatedSession> signInWithApiKey({
    required ServerConfig serverConfig,
    required String apiKey,
  }) async => _session();

  @override
  Future<AuthenticatedSession> signInWithSavedProfile({
    required String profileId,
    String? pin,
  }) async => _session();

  @override
  Future<void> setProfilePin({
    required String profileId,
    required bool enabled,
    String? pin,
  }) async {
    lastEnabled = enabled;
    lastPin = pin;
    profile = profile.copyWith(pinEnabled: enabled);
  }

  @override
  Future<void> signOut() async {}
}

AuthenticatedSession _session() {
  const serverUrl = 'https://photos.example.com';
  return AuthenticatedSession(
    serverConfig: ServerConfig(
      rawInput: serverUrl,
      serverUrl: Uri.parse(serverUrl),
      apiUrl: Uri.parse('$serverUrl/api'),
    ),
    accessToken: 'token',
    user: const UserProfile(
      id: 'user-1',
      email: 'owner@example.com',
      name: 'Owner',
    ),
  );
}

SavedProfile _savedProfile({required bool pinEnabled}) {
  return SavedProfile(
    id: 'profile-1',
    name: 'Owner',
    email: 'owner@example.com',
    serverConfig: _session().serverConfig,
    lastUsedAt: DateTime(2026),
    pinEnabled: pinEnabled,
  );
}
