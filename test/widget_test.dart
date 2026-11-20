import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/app.dart';
import 'package:immichtv/src/core/models/album_summary.dart';
import 'package:immichtv/src/core/models/authenticated_session.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/core/models/asset_sort_order.dart';
import 'package:immichtv/src/core/models/immich_auth_method.dart';
import 'package:immichtv/src/core/models/media_page.dart';
import 'package:immichtv/src/core/models/memory_summary.dart';
import 'package:immichtv/src/core/models/person_summary.dart';
import 'package:immichtv/src/core/models/place_summary.dart';
import 'package:immichtv/src/core/models/saved_profile.dart';
import 'package:immichtv/src/core/models/server_config.dart';
import 'package:immichtv/src/core/models/server_validation_result.dart';
import 'package:immichtv/src/core/models/user_profile.dart';
import 'package:immichtv/src/core/repositories/auth_repository.dart';
import 'package:immichtv/src/core/repositories/asset_image_repository.dart';
import 'package:immichtv/src/core/repositories/media_repository.dart';
import 'package:immichtv/src/core/repositories/server_repository.dart';
import 'package:immichtv/src/features/onboarding/widgets/onboarding_input_method.dart';
import 'package:immichtv/src/shared/presentation/widgets/authenticated_asset_image.dart';
import 'package:immichtv/src/shared/presentation/widgets/on_screen_keyboard/on_screen_keyboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows input selection before onboarding', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );

    await _settleAppFlow(tester);

    expect(find.text('Screen keyboard'), findsOneWidget);
    expect(find.text('Device keyboard'), findsOneWidget);
  });

  testWidgets('shows the saved profile picker when profiles exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final restoredSession = _demoSession();
    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(restoredSession: restoredSession),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );

    await _settleAppFlow(tester);

    expect(find.text(restoredSession.user.name), findsOneWidget);
    expect(find.textContaining(restoredSession.user.email), findsOneWidget);
    expect(find.text('Add profile'), findsOneWidget);
  });

  testWidgets('walks through validation and sign-in into home shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);
    await _advancePastInputSelection(tester);

    expect(find.widgetWithText(TextField, 'Immich server URL'), findsOneWidget);

    await _tapKeyboardAction(tester, 'Next');

    expect(find.text('Email / Password'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);

    await tester.tap(find.text('Email / Password'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);

    await _setFieldValueByLabel(tester, 'Email', 'family@example.com');
    await _setFieldValueByLabel(tester, 'Password', 'demo-password');
    await _tapKeyboardAction(tester, 'Continue');

    expect(find.text('Create a 4-digit PIN'), findsOneWidget);
    await _enterKeyboardDigits(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.text('Confirm your 4-digit PIN'), findsOneWidget);
    await _enterKeyboardDigits(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.text('Timeline'), findsWidgets);
    expect(find.textContaining('family@example.com'), findsOneWidget);
  });

  testWidgets('supports keyboard-style submit flow on onboarding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);
    await _advancePastInputSelection(tester);

    await _tapKeyboardAction(tester, 'Next');

    expect(find.text('Email / Password'), findsOneWidget);
    await tester.tap(find.text('Email / Password'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);

    await _setFieldValueByLabel(tester, 'Email', 'keyboard@example.com');
    await _setFieldValueByLabel(tester, 'Password', 'secret-password');
    await _tapKeyboardAction(tester, 'Continue');

    expect(find.text('Create a 4-digit PIN'), findsOneWidget);
    await _enterKeyboardDigits(tester, '2468');
    await tester.pumpAndSettle();

    expect(find.text('Confirm your 4-digit PIN'), findsOneWidget);
    await _enterKeyboardDigits(tester, '2468');
    await tester.pumpAndSettle();

    expect(find.text('Timeline'), findsWidgets);
    expect(find.textContaining('keyboard@example.com'), findsOneWidget);
  });

  testWidgets('supports API key onboarding flow', (tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);
    await _advancePastInputSelection(tester);

    await _tapKeyboardAction(tester, 'Next');
    await tester.tap(find.text('API Key'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'API key'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsNothing);

    await _setFieldValueByLabel(tester, 'API key', 'personal-api-key');
    await _tapKeyboardAction(tester, 'Continue');

    expect(find.text('Create a 4-digit PIN'), findsOneWidget);
    await _enterKeyboardDigits(tester, '2468');
    await tester.pumpAndSettle();
    await _enterKeyboardDigits(tester, '2468');
    await tester.pumpAndSettle();

    expect(find.text('Timeline'), findsWidgets);
    expect(find.textContaining('apikey@example.com'), findsOneWidget);
  });

  testWidgets('supports remote-only auth entry with the on-screen keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);
    await _advancePastInputSelection(tester);

    expect(find.byType(OnScreenKeyboard), findsOneWidget);

    final serverFieldFinder = find.widgetWithText(
      TextField,
      'Immich server URL',
    );
    final initialServerText = tester
        .widget<TextField>(serverFieldFinder)
        .controller!
        .text;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final updatedServerText = tester
        .widget<TextField>(serverFieldFinder)
        .controller!
        .text;
    expect(updatedServerText.length, greaterThan(initialServerText.length));

    await _tapKeyboardAction(tester, 'Next');
    expect(find.text('Email / Password'), findsOneWidget);
    await tester.tap(find.text('Email / Password'));
    await tester.pumpAndSettle();
    await _setFieldValueByLabel(tester, 'Email', 'remote@example.com');
    await _setFieldValueByLabel(tester, 'Password', 'remote-password');
    await _tapKeyboardAction(tester, 'Continue');

    expect(find.byType(OnScreenKeyboard), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Confirm your 4-digit PIN'), findsOneWidget);
  });

  testWidgets('tv keyboard next from email keeps password keyboard visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);
    await _advancePastInputSelection(
      tester,
      method: OnboardingInputMethod.tvKeyboard,
    );

    await _tapKeyboardAction(tester, 'Next');
    await tester.tap(find.text('Email / Password'));
    await tester.pumpAndSettle();

    await _setFieldValueByLabel(tester, 'Email', 'tv@example.com');
    await _tapKeyboardAction(tester, 'Next');

    expect(find.byType(OnScreenKeyboard), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      anyOf(contains('passwordKeyboard'), contains('passwordField')),
    );
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
  });

  testWidgets('input selection can be completed entirely with the remote', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.tv'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Immich server URL'), findsOneWidget);
  });

  testWidgets('input selection cards move focus with left and right arrows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.tv'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.native'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.tv'),
    );
  });

  testWidgets('input selection cards can be selected with enter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.native'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(OnScreenKeyboard), findsNothing);
    expect(find.text('Immich server URL'), findsOneWidget);
  });

  testWidgets('stacked input selection moves down through cards first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.native'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.tv'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.native'),
    );

    // Another down press at the bottom card is a no-op.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.native'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.tv'),
    );

    // Likewise, moving up from the first card keeps focus in place.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('inputMethod.tv'),
    );
  });

  testWidgets('device keyboard can be selected before onboarding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);
    await _advancePastInputSelection(
      tester,
      method: OnboardingInputMethod.nativeKeyboard,
    );

    expect(find.byType(OnScreenKeyboard), findsNothing);

    final serverFieldFinder = find.widgetWithText(
      TextField,
      'Immich server URL',
    );
    final serverField = tester.widget<TextField>(serverFieldFinder);
    expect(serverField.readOnly, isFalse);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('serverField'),
    );

    await tester.tap(serverFieldFinder);
    await tester.pump();
    await tester.enterText(serverFieldFinder, 'https://photos.example.com');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(serverFieldFinder).controller!.text,
      'https://photos.example.com',
    );
  });

  testWidgets('desktop-style onboarding defaults to device keyboard', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    try {
      await tester.pumpWidget(
        ImmichTvApp(
          authRepository: FakeAuthRepository(),
          assetImageRepository: FakeAssetImageRepository(),
          serverRepository: FakeServerRepository(),
          mediaRepository: FakeMediaRepository(),
        ),
      );
      await _settleAppFlow(tester);

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('inputMethod.native'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(OnScreenKeyboard), findsNothing);

      final serverFieldFinder = find.widgetWithText(
        TextField,
        'Immich server URL',
      );
      expect(serverFieldFinder, findsOneWidget);
      expect(tester.widget<TextField>(serverFieldFinder).readOnly, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('device keyboard next from email keeps password field editable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ImmichTvApp(
        authRepository: FakeAuthRepository(),
        assetImageRepository: FakeAssetImageRepository(),
        serverRepository: FakeServerRepository(),
        mediaRepository: FakeMediaRepository(),
      ),
    );
    await _settleAppFlow(tester);
    await _advancePastInputSelection(
      tester,
      method: OnboardingInputMethod.nativeKeyboard,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Immich server URL'),
      'https://photos.example.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Email / Password'));
    await tester.pumpAndSettle();

    final emailFieldFinder = find.widgetWithText(TextField, 'Email');
    await tester.tap(emailFieldFinder);
    await tester.pumpAndSettle();
    await tester.enterText(emailFieldFinder, 'keyboard@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('passwordField'),
    );

    final passwordFieldFinder = find.widgetWithText(TextField, 'Password');
    final passwordField = tester.widget<TextField>(passwordFieldFinder);
    expect(passwordField.readOnly, isFalse);

    await tester.enterText(passwordFieldFinder, 'secret-password');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(passwordFieldFinder).controller!.text,
      'secret-password',
    );
  });

  testWidgets(
    'device keyboard arrow keys do not move focus out of email field',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ImmichTvApp(
          authRepository: FakeAuthRepository(),
          assetImageRepository: FakeAssetImageRepository(),
          serverRepository: FakeServerRepository(),
          mediaRepository: FakeMediaRepository(),
        ),
      );
      await _settleAppFlow(tester);
      await _advancePastInputSelection(
        tester,
        method: OnboardingInputMethod.nativeKeyboard,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Immich server URL'),
        'https://photos.example.com',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Email / Password'));
      await tester.pumpAndSettle();

      final emailFieldFinder = find.widgetWithText(TextField, 'Email');
      await tester.tap(emailFieldFinder);
      await tester.pumpAndSettle();
      await tester.enterText(emailFieldFinder, 'keyboard@example.com');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('emailField'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('emailField'),
      );
    },
  );

  testWidgets('supports remote-style navigation in the sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSignedInApp(tester, mediaRepository: FakeMediaRepository());

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Summer Trip'), findsWidgets);
    expect(find.text('42 assets'), findsOneWidget);
  });

  testWidgets('switches between library sections and shows empty states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSignedInApp(tester, mediaRepository: FakeMediaRepository());

    expect(_findAssetThumbnail('asset-1'), findsOneWidget);

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Summer Trip'), findsWidgets);
    expect(find.text('42 assets'), findsOneWidget);
    expect(_findAssetThumbnail('asset-1'), findsOneWidget);

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_findAssetThumbnail('favorite-1'), findsOneWidget);
  });

  testWidgets('switches to the people tab and shows person assets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSignedInApp(tester, mediaRepository: FakeMediaRepository());

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Avery'), findsWidgets);
    expect(find.text('3 assets'), findsWidgets);
    expect(_findAssetThumbnail('person-asset-1'), findsOneWidget);
  });

  testWidgets('shows memories and opens them in the fullscreen viewer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final memory = MemorySummary(
      id: 'memory-1',
      title: '2023',
      subtitle: '3 years ago',
      memoryAt: DateTime.utc(2023, 11, 19),
      assets: [
        AssetSummary(
          id: 'memory-asset-1',
          thumbnailUrls: [
            'https://photos.example.com/api/assets/memory-asset-1/thumbnail?size=preview',
          ],
          displayUrls: [
            'https://photos.example.com/api/assets/memory-asset-1/original',
          ],
          type: 'IMAGE',
          createdAt: DateTime.utc(2023, 11, 19),
        ),
      ],
    );

    await _pumpSignedInApp(
      tester,
      mediaRepository: FakeMediaRepository(memories: [memory]),
    );

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    for (var index = 0; index < 4; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('2023'), findsWidgets);
    expect(find.text('November 19, 2023'), findsWidgets);
    expect(find.textContaining('1 memory'), findsOneWidget);
    expect(_findAssetThumbnail('memory-asset-1'), findsOneWidget);

    final thumbnailFinder = _findAssetThumbnail('memory-asset-1').first;
    await tester.ensureVisible(thumbnailFinder);
    await tester.tap(thumbnailFinder, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.close_rounded), findsWidgets);
  });

  testWidgets('groups memories from the same year into one folder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    MemorySummary buildMemory(String id, DateTime date) {
      return MemorySummary(
        id: id,
        title: '2023',
        subtitle: '3 years ago',
        memoryAt: date,
        assets: [
          AssetSummary(
            id: '$id-asset',
            thumbnailUrls: [
              'https://photos.example.com/api/assets/$id-asset/thumbnail?size=preview',
            ],
            displayUrls: [
              'https://photos.example.com/api/assets/$id-asset/original',
            ],
            type: 'IMAGE',
            createdAt: date,
          ),
        ],
      );
    }

    await _pumpSignedInApp(
      tester,
      mediaRepository: FakeMediaRepository(
        memories: [
          buildMemory('memory-a', DateTime.utc(2023, 3, 4)),
          buildMemory('memory-b', DateTime.utc(2023, 11, 19)),
        ],
      ),
    );

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    for (var index = 0; index < 4; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // One rail folder plus one grid heading, not one folder per memory.
    expect(find.text('2023'), findsNWidgets(2));
    expect(find.textContaining('2 memories'), findsOneWidget);
    expect(_findAssetThumbnail('memory-a-asset'), findsOneWidget);
    expect(_findAssetThumbnail('memory-b-asset'), findsOneWidget);
  });

  testWidgets('shows places grouped by city with a photo grid', (tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final preview = AssetSummary(
      id: 'place-asset-1',
      thumbnailUrls: [
        'https://photos.example.com/api/assets/place-asset-1/thumbnail?size=preview',
      ],
      displayUrls: [
        'https://photos.example.com/api/assets/place-asset-1/original',
      ],
      type: 'IMAGE',
      createdAt: DateTime.utc(2025, 6, 1),
      city: 'Lisbon',
      country: 'Portugal',
    );
    final place = PlaceSummary(
      id: 'Lisbon|Portugal',
      city: 'Lisbon',
      state: '',
      country: 'Portugal',
      preview: preview,
    );

    await _pumpSignedInApp(
      tester,
      mediaRepository: FakeMediaRepository(places: [place]),
    );

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    for (var index = 0; index < 5; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Lisbon'), findsWidgets);
    expect(find.text('Portugal'), findsWidgets);
    expect(_findAssetThumbnail('place-asset-1'), findsWidgets);
  });

  testWidgets('loads the next timeline page as the grid scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSignedInApp(
      tester,
      mediaRepository: FakeMediaRepository(paginatedTimeline: true),
    );

    expect(_findAssetThumbnail('asset-1'), findsOneWidget);
    expect(_findAssetThumbnail('asset-3'), findsNothing);

    await tester.drag(find.byType(GridView).first, const Offset(0, -1200));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(_findAssetThumbnail('asset-3'), findsOneWidget);
  });

  testWidgets('opens the fullscreen asset viewer and navigates forward', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSignedInApp(tester, mediaRepository: FakeMediaRepository());

    final firstAssetLabel = _findAssetThumbnail('asset-1').first;
    await tester.ensureVisible(firstAssetLabel);
    await tester.tap(firstAssetLabel, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close_rounded), findsWidgets);
    expect(find.byIcon(Icons.slideshow_rounded), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.slideshow_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(find.text('2026-11-10'), findsOneWidget);
  });

  testWidgets('shows a video scrubber action instead of slideshow for videos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSignedInApp(
      tester,
      mediaRepository: FakeMediaRepository(includeVideoAsset: true),
    );

    final videoAssetLabel = _findAssetThumbnail('video-1').first;
    await tester.ensureVisible(videoAssetLabel);
    await tester.tap(videoAssetLabel, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byIcon(Icons.pause_rounded).evaluate().length +
          find.byIcon(Icons.play_arrow_rounded).evaluate().length,
      1,
    );
    expect(find.byIcon(Icons.video_settings_rounded), findsOneWidget);
    expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
    expect(find.byIcon(Icons.slideshow_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsWidgets);
  });

  testWidgets('starts a slideshow with playback controls', (tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSignedInApp(tester, mediaRepository: FakeMediaRepository());

    final firstAssetLabel = _findAssetThumbnail('asset-1').first;
    await tester.ensureVisible(firstAssetLabel);
    await tester.tap(firstAssetLabel, warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.slideshow_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Start slideshow'), findsOneWidget);
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('2026-11-09'), findsOneWidget);
  });
}

Future<void> _settleAppFlow(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pumpAndSettle();
}

Future<void> _advancePastInputSelection(
  WidgetTester tester, {
  OnboardingInputMethod method = OnboardingInputMethod.tvKeyboard,
}) async {
  final optionLabel = switch (method) {
    OnboardingInputMethod.tvKeyboard => 'Screen keyboard',
    OnboardingInputMethod.nativeKeyboard => 'Device keyboard',
  };
  final optionFinder = find.text(optionLabel);
  await tester.ensureVisible(optionFinder);
  await tester.tap(optionFinder);
  await tester.pumpAndSettle();

  // Selecting a card immediately advances to the onboarding form; the
  // selector no longer has a separate Continue button.
}

Future<void> _setFieldValueByLabel(
  WidgetTester tester,
  String label,
  String value,
) async {
  final fieldFinder = find.widgetWithText(
    TextField,
    label,
    skipOffstage: false,
  );
  await tester.ensureVisible(fieldFinder);
  final field = tester.widget<TextField>(fieldFinder);
  field.controller!.text = value;
  field.focusNode?.requestFocus();
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _enterKeyboardDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    final digitFinder = find.descendant(
      of: find.byType(OnScreenKeyboard),
      matching: find.text(digit, skipOffstage: false),
    );
    await tester.ensureVisible(digitFinder.first);
    await tester.tap(digitFinder.first);
    await tester.pump();
    await tester.pumpAndSettle();
  }
}

Future<void> _tapKeyboardAction(WidgetTester tester, String label) async {
  final buttonFinder = find.descendant(
    of: find.byType(OnScreenKeyboard),
    matching: find.text(label, skipOffstage: false),
  );
  if (buttonFinder.evaluate().isEmpty) {
    fail('Could not find keyboard action "$label"');
  }
  await tester.ensureVisible(buttonFinder.first);
  await tester.tap(buttonFinder.first);
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _pumpSignedInApp(
  WidgetTester tester, {
  required MediaRepository mediaRepository,
}) async {
  await tester.pumpWidget(
    ImmichTvApp(
      authRepository: FakeAuthRepository(),
      assetImageRepository: FakeAssetImageRepository(),
      serverRepository: FakeServerRepository(),
      mediaRepository: mediaRepository,
    ),
  );
  await _settleAppFlow(tester);
  await _advancePastInputSelection(tester);

  await _tapKeyboardAction(tester, 'Next');
  await tester.tap(find.text('Email / Password'));
  await tester.pumpAndSettle();
  await _setFieldValueByLabel(tester, 'Email', 'family@example.com');
  await _setFieldValueByLabel(tester, 'Password', 'demo-password');
  await _tapKeyboardAction(tester, 'Continue');
  await _enterKeyboardDigits(tester, '1234');
  await tester.pumpAndSettle();
  await _enterKeyboardDigits(tester, '1234');
  await tester.pumpAndSettle();
}

Finder _findAssetThumbnail(String assetId) {
  return find.byWidgetPredicate((widget) {
    return widget is AuthenticatedAssetImage &&
        widget.imageUrls.any((url) => url.contains(assetId));
  });
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.restoredSession});

  final AuthenticatedSession? restoredSession;

  @override
  Future<AuthenticatedSession> signIn({
    required ServerConfig serverConfig,
    required String email,
    required String password,
  }) async {
    return AuthenticatedSession(
      serverConfig: serverConfig,
      accessToken: 'token',
      user: UserProfile(id: '1', email: email, name: 'Living Room'),
    );
  }

  @override
  Future<AuthenticatedSession> signInWithApiKey({
    required ServerConfig serverConfig,
    required String apiKey,
  }) async {
    return AuthenticatedSession(
      serverConfig: serverConfig,
      accessToken: apiKey,
      user: const UserProfile(
        id: 'api-user',
        email: 'apikey@example.com',
        name: 'Living Room',
      ),
      authMethod: ImmichAuthMethod.apiKey,
    );
  }

  @override
  Future<List<SavedProfile>> getSavedProfiles() async {
    if (restoredSession == null) {
      return const <SavedProfile>[];
    }

    return [
      SavedProfile(
        id: 'saved-profile',
        name: restoredSession!.user.name,
        email: restoredSession!.user.email,
        serverConfig: restoredSession!.serverConfig,
        lastUsedAt: DateTime(2025),
      ),
    ];
  }

  @override
  Future<void> saveProfile({
    required AuthenticatedSession session,
    String? password,
    String? apiKey,
    String? pin,
  }) async {}

  @override
  Future<AuthenticatedSession> signInWithSavedProfile({
    required String profileId,
    String? pin,
  }) async {
    return restoredSession ?? _demoSession();
  }

  @override
  Future<void> setProfilePin({
    required String profileId,
    required bool enabled,
    String? pin,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class FakeServerRepository implements ServerRepository {
  @override
  Future<ServerValidationResult> validateServer(String rawInput) async {
    final serverConfig = ServerConfig(
      rawInput: rawInput,
      serverUrl: Uri.parse('https://photos.example.com'),
      apiUrl: Uri.parse('https://photos.example.com/api'),
    );
    return ServerValidationResult(
      serverConfig: serverConfig,
      pingPath: 'server/ping',
    );
  }
}

class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository({
    this.paginatedTimeline = false,
    this.includeVideoAsset = false,
    this.memories = const <MemorySummary>[],
    this.places = const <PlaceSummary>[],
  });

  final bool paginatedTimeline;
  final bool includeVideoAsset;
  final List<MemorySummary> memories;
  final List<PlaceSummary> places;

  @override
  Future<List<AlbumSummary>> fetchAlbums(AuthenticatedSession session) async =>
      [const AlbumSummary(id: 'album-1', name: 'Summer Trip', assetCount: 42)];

  @override
  Future<List<MemorySummary>> fetchMemories(AuthenticatedSession session) async =>
      memories;

  @override
  Future<List<PersonSummary>> fetchPeople(AuthenticatedSession session) async =>
      const [
        PersonSummary(
          id: 'person-1',
          name: 'Avery',
          assetCount: 3,
          thumbnailUrls: ['mock://person-1?palette=dusk&variant=thumbnail'],
        ),
      ];

  @override
  Future<List<PlaceSummary>> fetchPlaces(AuthenticatedSession session) async =>
      places;

  @override
  Future<MediaPage<AssetSummary>> fetchPlaceAssetsPage(
    AuthenticatedSession session, {
    required PlaceSummary place,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => MediaPage(items: [place.preview]);

  @override
  Future<MediaPage<AssetSummary>> fetchAlbumAssetsPage(
    AuthenticatedSession session, {
    required String albumId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => MediaPage(items: _timelinePageOne);

  @override
  Future<MediaPage<AssetSummary>> fetchFavoritesPage(
    AuthenticatedSession session, {
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 60,
  }) async => MediaPage(
    items: [
      AssetSummary(
        id: 'favorite-1',
        thumbnailUrls: const [
          'mock://favorite-1?palette=ember&variant=thumbnail',
          'mock://favorite-1?palette=ember&variant=thumbnail',
        ],
        displayUrls: const ['mock://favorite-1?palette=ember&variant=display'],
        type: 'IMAGE',
        createdAt: DateTime(2024, 10, 2),
      ),
    ],
  );

  @override
  Future<MediaPage<AssetSummary>> fetchPersonAssetsPage(
    AuthenticatedSession session, {
    required String personId,
    AssetSortOrder sortOrder = AssetSortOrder.newestFirst,
    String? page,
    int pageSize = 120,
  }) async => MediaPage(
    items: [
      AssetSummary(
        id: 'person-asset-1',
        thumbnailUrls: const [
          'mock://person-asset-1?palette=forest&variant=thumbnail',
          'mock://person-asset-1?palette=forest&variant=thumbnail',
        ],
        displayUrls: const [
          'mock://person-asset-1?palette=forest&variant=display',
        ],
        type: 'IMAGE',
        createdAt: DateTime(2026, 10, 1),
      ),
      AssetSummary(
        id: 'person-asset-2',
        thumbnailUrls: const [
          'mock://person-asset-2?palette=sea-glass&variant=thumbnail',
          'mock://person-asset-2?palette=sea-glass&variant=thumbnail',
        ],
        displayUrls: const [
          'mock://person-asset-2?palette=sea-glass&variant=display',
        ],
        type: 'IMAGE',
        createdAt: DateTime(2026, 10, 2),
      ),
      AssetSummary(
        id: 'person-asset-3',
        thumbnailUrls: const [
          'mock://person-asset-3?palette=sunrise&variant=thumbnail',
          'mock://person-asset-3?palette=sunrise&variant=thumbnail',
        ],
        displayUrls: const [
          'mock://person-asset-3?palette=sunrise&variant=display',
        ],
        type: 'IMAGE',
        createdAt: DateTime(2026, 10, 3),
      ),
    ],
  );

  @override
  Future<MediaPage<AssetSummary>> fetchTimelinePage(
    AuthenticatedSession session, {
    String? page,
    int pageSize = 60,
    int? year,
  }) async {
    if (includeVideoAsset) {
      return MediaPage(items: _videoTimelinePageOne);
    }

    if (!paginatedTimeline) {
      return MediaPage(items: _timelinePageOne);
    }

    return switch (page) {
      null => MediaPage(items: _timelinePageOne, nextPage: '2'),
      '2' => MediaPage(items: _timelinePageTwo),
      _ => const MediaPage(items: []),
    };
  }
}

class FakeAssetImageRepository implements AssetImageRepository {
  @override
  Future<void> prefetchImages({
    required List<List<String>> urls,
    required String accessToken,
    required ImmichAuthMethod authMethod,
  }) async {}
}

AuthenticatedSession _demoSession() {
  return AuthenticatedSession(
    serverConfig: ServerConfig(
      rawInput: 'https://photos.example.com',
      serverUrl: Uri.parse('https://photos.example.com'),
      apiUrl: Uri.parse('https://photos.example.com/api'),
    ),
    accessToken: 'token',
    user: const UserProfile(
      id: '1',
      email: 'family@example.com',
      name: 'Living Room',
    ),
  );
}

final List<AssetSummary> _timelinePageOne = [
  AssetSummary(
    id: 'asset-1',
    thumbnailUrls: const [
      'mock://asset-1?palette=sea-glass&variant=thumbnail',
      'mock://asset-1?palette=sea-glass&variant=thumbnail',
    ],
    displayUrls: const ['mock://asset-1?palette=sea-glass&variant=display'],
    type: 'IMAGE',
    createdAt: DateTime(2026, 11, 9),
  ),
  AssetSummary(
    id: 'asset-2',
    thumbnailUrls: const [
      'mock://asset-2?palette=sunrise&variant=thumbnail',
      'mock://asset-2?palette=sunrise&variant=thumbnail',
    ],
    displayUrls: const ['mock://asset-2?palette=sunrise&variant=display'],
    type: 'IMAGE',
    createdAt: DateTime(2026, 11, 10),
  ),
];

final List<AssetSummary> _timelinePageTwo = [
  AssetSummary(
    id: 'asset-3',
    thumbnailUrls: const [
      'mock://asset-3?palette=forest&variant=thumbnail',
      'mock://asset-3?palette=forest&variant=thumbnail',
    ],
    displayUrls: const ['mock://asset-3?palette=forest&variant=display'],
    type: 'IMAGE',
    createdAt: DateTime(2026, 11, 11),
  ),
];

final List<AssetSummary> _videoTimelinePageOne = [
  AssetSummary(
    id: 'video-1',
    thumbnailUrls: const [
      'mock://video-1?palette=dusk&variant=thumbnail',
      'mock://video-1?palette=dusk&variant=thumbnail',
    ],
    displayUrls: const [
      'https://photos.example.com/api/assets/video-1/video/playback',
    ],
    type: 'VIDEO',
    createdAt: DateTime(2026, 11, 12),
  ),
];
