import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/platform/review_prompt/shared_preferences_review_prompt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('prompts after three successful logins by default', () async {
    final service = SharedPreferencesReviewPromptService(
      debugAlwaysPrompt: false,
    );

    await service.registerAppBoot();
    await service.registerSuccessfulLogin();
    await service.registerSuccessfulLogin();
    await service.registerSuccessfulLogin();

    final status = await service.getStatus();

    expect(status.loginCount, 3);
    expect(status.bootCount, 1);
    expect(status.shouldPrompt, isTrue);
  });

  test('defers the next prompt by four boots after not now', () async {
    final service = SharedPreferencesReviewPromptService(
      debugAlwaysPrompt: false,
    );

    await service.registerAppBoot();
    await service.registerSuccessfulLogin();
    await service.registerSuccessfulLogin();
    await service.registerSuccessfulLogin();

    await service.deferPrompt();

    expect((await service.getStatus()).shouldPrompt, isFalse);

    await service.registerAppBoot();
    await service.registerAppBoot();
    await service.registerAppBoot();
    expect((await service.getStatus()).shouldPrompt, isFalse);

    await service.registerAppBoot();
    expect((await service.getStatus()).shouldPrompt, isTrue);
  });

  test('stops prompting after completion', () async {
    final service = SharedPreferencesReviewPromptService(
      debugAlwaysPrompt: false,
    );

    await service.registerAppBoot();
    await service.registerSuccessfulLogin();
    await service.registerSuccessfulLogin();
    await service.registerSuccessfulLogin();
    await service.completePrompt();

    final status = await service.getStatus();

    expect(status.hasCompleted, isTrue);
    expect(status.shouldPrompt, isFalse);
  });
}
