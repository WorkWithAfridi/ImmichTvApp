import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/app.dart';
import 'package:immichtv/src/core/models/album_summary.dart';
import 'package:immichtv/src/core/models/asset_sort_order.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/immich_auth_method.dart';
import 'package:immichtv/src/core/models/media_page.dart';
import 'package:immichtv/src/core/models/memory_summary.dart';
import 'package:immichtv/src/core/models/person_summary.dart';
import 'package:immichtv/src/core/models/place_summary.dart';
import 'package:immichtv/src/core/models/saved_profile.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/server_validation_result.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/core/repositories/asset_image_repository.dart';
import 'package:immichtv/src/core/repositories/auth_repository.dart';
import 'package:immichtv/src/core/repositories/media_repository.dart';
import 'package:immichtv/src/core/repositories/server_repository.dart';
import 'package:immichtv/src/shared/presentation/widgets/on_screen_keyboard/on_screen_keyboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'onboarding, browsing, switching profiles and signing out work together',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final auth = _IntegrationAuthRepository();
      await tester.pumpWidget(
        ImmichTvApp(
          authRepository: auth,
          assetImageRepository: const _NoopAssetImageRepository(),
          serverRepository: const _FakeServerRepository(),
          mediaRepository: const _FakeMediaRepository(),
        ),
      );
      await _settle(tester);

      // Bootstrap -> onboarding.
      expect(find.text('Screen keyboard'), findsOneWidget);
      await tester.tap(find.text('Screen keyboard'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Immich server URL'),
        findsOneWidget,
      );

      await _setField(tester, 'Immich server URL', 'https://photos.example.com');
      await _tapKeyboardAction(tester, 'Next');
      expect(find.text('Email / Password'), findsOneWidget);

      await tester.tap(find.text('Email / Password'));
      await tester.pumpAndSettle();
      await _setField(tester, 'Email', 'family@example.com');
      await _setField(tester, 'Password', 'demo-password');
      await _tapKeyboardAction(tester, 'Continue');

      // Optional PIN enrollment.
      expect(find.text('Create a 4-digit PIN'), findsOneWidget);
      await _enterDigits(tester, '1234');
      expect(find.text('Confirm your 4-digit PIN'), findsOneWidget);
      await _enterDigits(tester, '1234');
      expect(find.text('Timeline'), findsWidgets);

      // Browse a different library tab.
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Summer Trip'), findsWidgets);

      // Sign out returns to the saved-profile picker.
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Add profile'), findsOneWidget);
      expect(find.textContaining('family@example.com'), findsOneWidget);

      // Reopening the profile requires its PIN and returns to the library.
      await tester.tap(find.textContaining('family@example.com').first);
      await tester.pumpAndSettle();
      expect(find.text('Enter your 4-digit PIN'), findsOneWidget);
      await _enterDigits(tester, '1234');
      await tester.pumpAndSettle();
      expect(find.text('Timeline'), findsWidgets);
    },
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pumpAndSettle();
}

Future<void> _setField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final finder = find.widgetWithText(TextField, label, skipOffstage: false);
  await tester.ensureVisible(finder);
  final field = tester.widget<TextField>(finder);
  field.controller!.text = value;
  field.focusNode?.requestFocus();
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _tapKeyboardAction(WidgetTester tester, String label) async {
  final finder = find.descendant(
    of: find.byType(OnScreenKeyboard),
    matching: find.text(label, skipOffstage: false),
  );
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _enterDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    final finder = find.descendant(
      of: find.byType(OnScreenKeyboard),
      matching: find.text(digit, skipOffstage: false),
    );
    await tester.tap(finder.first);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _IntegrationAuthRepository implements AuthRepository {
  final List<SavedProfile> _profiles = [];
  final Map<String, String> _pins = {};

  @override
  Future<AuthenticatedSession> signIn({
    required ServerConfig serverConfig,
    required String email,
    required String password,
  }) async => _session(serverConfig, email);

  @override
  Future<AuthenticatedSession> signInWithApiKey({
    required ServerConfig serverConfig,
    required String apiKey,
  }) async => _session(serverConfig, 'apikey@example.com');

  @override
  Future<List<SavedProfile>> getSavedProfiles() async =>
      List<SavedProfile>.from(_profiles);

  @override
  Future<void> saveProfile({
    required AuthenticatedSession session,
    String? password,
    String? apiKey,
    String? pin,
  }) async {
    _profiles.removeWhere((profile) => profile.id == session.user.id);
    _profiles.add(
      SavedProfile(
        id: session.user.id,
        name: session.user.name,
        email: session.user.email,
        serverConfig: session.serverConfig,
        lastUsedAt: DateTime(2026),
      ),
    );
    if (pin != null) {
      _pins[session.user.id] = pin;
    }
  }

  @override
  Future<AuthenticatedSession> signInWithSavedProfile({
    required String profileId,
    String? pin,
  }) async {
    final profile = _profiles.firstWhere((item) => item.id == profileId);
    if (_pins.containsKey(profileId) && _pins[profileId] != pin) {
      throw StateError('invalid pin');
    }
    return _session(profile.serverConfig, profile.email);
  }

  @override
  Future<void> setProfilePin({
    required String profileId,
    required bool enabled,
    String? pin,
  }) async {
    if (enabled && pin != null) {
      _pins[profileId] = pin;
    } else {
      _pins.remove(profileId);
    }
  }

  @override
  Future<void> signOut() async {}

  AuthenticatedSession _session(ServerConfig serverConfig, String email) {
    return AuthenticatedSession(
      serverConfig: serverConfig,
      accessToken: 'token',
      user: UserProfile(id: 'user-1', email: email, name: 'Living Room'),
    );
  }
}

class _FakeServerRepository implements ServerRepository {
  const _FakeServerRepository();

  @override
  Future<ServerValidationResult> validateServer(String rawInput) async {
    final uri = Uri.parse(rawInput);
    return ServerValidationResult(
      serverConfig: ServerConfig(
        rawInput: rawInput,
        serverUrl: uri,
        apiUrl: Uri.parse('$rawInput/api'),
      ),
      pingPath: 'server/ping',
    );
  }
}

class _NoopAssetImageRepository implements AssetImageRepository {
  const _NoopAssetImageRepository();

  @override
  Future<void> prefetchImages({
    required List<List<String>> urls,
    required String accessToken,
    required ImmichAuthMethod authMethod,
  }) async {}
}

class _FakeMediaRepository implements MediaRepository {
  const _FakeMediaRepository();

  @override
  Future<List<AlbumSummary>> fetchAlbums(AuthenticatedSession session) async =>
      const [
        AlbumSummary(id: 'album-1', name: 'Summer Trip', assetCount: 42),
      ];

  @override
  Future<List<PersonSummary>> fetchPeople(AuthenticatedSession session) async =>
      const [];

  @override
  Future<List<MemorySummary>> fetchMemories(AuthenticatedSession session) async =>
      const [];

  @override
  Future<List<PlaceSummary>> fetchPlaces(AuthenticatedSession session) async =>
      const <PlaceSummary>[];

  @override
  Future<MediaPage<AssetSummary>> fetchPlaceAssetsPage(
    AuthenticatedSession session, {
    required PlaceSummary place,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => const MediaPage(items: []);

  @override
  Future<MediaPage<AssetSummary>> fetchAlbumAssetsPage(
    AuthenticatedSession session, {
    required String albumId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => const MediaPage(items: []);

  @override
  Future<MediaPage<AssetSummary>> fetchFavoritesPage(
    AuthenticatedSession session, {
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 30,
  }) async => const MediaPage(items: []);

  @override
  Future<MediaPage<AssetSummary>> fetchPersonAssetsPage(
    AuthenticatedSession session, {
    required String personId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => const MediaPage(items: []);

  @override
  Future<MediaPage<AssetSummary>> fetchTimelinePage(
    AuthenticatedSession session, {
    String? page,
    int pageSize = 30,
    int? year,
  }) async => const MediaPage(items: []);
}
