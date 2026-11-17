import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/saved_profile.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/core/repositories/auth_repository.dart';
import 'package:immichtv/src/features/home/home_screen.dart';
import 'package:immichtv/src/features/settings/cubit/settings_cubit.dart';
import 'package:immichtv/src/shared/presentation/widgets/on_screen_keyboard/on_screen_keyboard.dart';

void main() {
  testWidgets(
    'settings screen can turn PIN protection on with the on-screen keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final repository = _FakeAuthRepository(
        profile: _savedProfile(pinEnabled: false),
      );
      final session = _session();

      await tester.pumpWidget(
        RepositoryProvider<AuthRepository>.value(
          value: repository,
          child: MaterialApp(
            home: BlocProvider(
              create: (_) =>
                  SettingsCubit(authRepository: repository, session: session),
              child: Scaffold(
                body: SettingsScreen(
                  session: session,
                  isSidebarOpen: false,
                  primaryContentFocusNode: FocusNode(),
                  menuToggleFocusNode: FocusNode(),
                  onToggleSidebar: () {},
                  onOpenSidebar: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Profile PIN'), findsOneWidget);
      expect(
        find.text('No PIN required when switching to this profile.'),
        findsOneWidget,
      );

      final onFinder = find.text('On');
      await tester.ensureVisible(onFinder);
      await tester.tap(onFinder);
      await tester.pumpAndSettle();

      expect(find.text('Create a 4-digit PIN'), findsOneWidget);
      for (final digit in '1357'.split('')) {
        final digitFinder = find.descendant(
          of: find.byType(OnScreenKeyboard),
          matching: find.text(digit),
        );
        await tester.tap(digitFinder.first);
        await tester.pump();
      }

      final saveFinder = find.text('Save PIN');
      await tester.ensureVisible(saveFinder);
      await tester.pumpAndSettle();
      await tester.tap(saveFinder);
      await tester.pumpAndSettle();

      expect(repository.lastEnabled, isTrue);
      expect(repository.lastPin, '1357');
      expect(
        find.text('A PIN is required when switching to this profile.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('arrow keys focus the PIN pills and enter activates them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final repository = _FakeAuthRepository(
      profile: _savedProfile(pinEnabled: false),
    );
    final session = _session();

    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: repository,
        child: MaterialApp(
          home: BlocProvider(
            create: (_) =>
                SettingsCubit(authRepository: repository, session: session),
            child: Scaffold(
              body: SettingsScreen(
                session: session,
                isSidebarOpen: false,
                primaryContentFocusNode: FocusNode(),
                menuToggleFocusNode: FocusNode(),
                onToggleSidebar: () {},
                onOpenSidebar: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The initially focused pill is "Off" (PIN disabled). Move right to "On".
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Create a 4-digit PIN'), findsOneWidget);

    // Arrow left from the focused "Save PIN" chip returns to "Cancel".
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Create a 4-digit PIN'), findsNothing);
    expect(repository.lastEnabled, isNull);
  });

  testWidgets('settings screen can turn PIN protection off', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final repository = _FakeAuthRepository(
      profile: _savedProfile(pinEnabled: true),
    );
    final session = _session();

    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: repository,
        child: MaterialApp(
          home: BlocProvider(
            create: (_) =>
                SettingsCubit(authRepository: repository, session: session),
            child: Scaffold(
              body: SettingsScreen(
                session: session,
                isSidebarOpen: false,
                primaryContentFocusNode: FocusNode(),
                menuToggleFocusNode: FocusNode(),
                onToggleSidebar: () {},
                onOpenSidebar: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final offFinder = find.text('Off');
    await tester.ensureVisible(offFinder);
    await tester.tap(offFinder);
    await tester.pumpAndSettle();

    expect(repository.lastEnabled, isFalse);
    expect(
      find.text('No PIN required when switching to this profile.'),
      findsOneWidget,
    );
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
