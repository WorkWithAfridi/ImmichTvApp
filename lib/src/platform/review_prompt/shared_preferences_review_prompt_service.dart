import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/review_prompt_service.dart';

class SharedPreferencesReviewPromptService implements ReviewPromptService {
  SharedPreferencesReviewPromptService({
    this.initialLoginThreshold = 3,
    this.deferBootCount = 4,
    bool? debugAlwaysPrompt,
  }) : _debugAlwaysPrompt = debugAlwaysPrompt ?? kDebugMode;

  static const _loginCountKey = 'immichtv.review_prompt.login_count';
  static const _bootCountKey = 'immichtv.review_prompt.boot_count';
  static const _nextEligibleBootKey =
      'immichtv.review_prompt.next_eligible_boot';
  static const _completedKey = 'immichtv.review_prompt.completed';

  final int initialLoginThreshold;
  final int deferBootCount;
  final bool _debugAlwaysPrompt;

  @override
  Future<void> registerAppBoot() async {
    final prefs = await SharedPreferences.getInstance();
    final nextBootCount = (prefs.getInt(_bootCountKey) ?? 0) + 1;
    await prefs.setInt(_bootCountKey, nextBootCount);
  }

  @override
  Future<void> registerSuccessfulLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final nextLoginCount = (prefs.getInt(_loginCountKey) ?? 0) + 1;
    await prefs.setInt(_loginCountKey, nextLoginCount);
  }

  @override
  Future<ReviewPromptStatus> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final loginCount = prefs.getInt(_loginCountKey) ?? 0;
    final bootCount = prefs.getInt(_bootCountKey) ?? 0;
    final hasCompleted = prefs.getBool(_completedKey) ?? false;
    final nextEligibleBoot = prefs.getInt(_nextEligibleBootKey) ?? 0;

    return ReviewPromptStatus(
      loginCount: loginCount,
      bootCount: bootCount,
      hasCompleted: hasCompleted,
      shouldPrompt:
          _debugAlwaysPrompt ||
          (!hasCompleted &&
              loginCount >= initialLoginThreshold &&
              bootCount >= nextEligibleBoot),
    );
  }

  @override
  Future<void> deferPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final bootCount = prefs.getInt(_bootCountKey) ?? 0;
    await prefs.setInt(_nextEligibleBootKey, bootCount + deferBootCount);
  }

  @override
  Future<void> completePrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }
}
