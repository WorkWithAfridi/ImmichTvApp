class ReviewPromptStatus {
  const ReviewPromptStatus({
    required this.loginCount,
    required this.bootCount,
    required this.hasCompleted,
    required this.shouldPrompt,
  });

  final int loginCount;
  final int bootCount;
  final bool hasCompleted;
  final bool shouldPrompt;
}

abstract class ReviewPromptService {
  Future<void> registerAppBoot();

  Future<void> registerSuccessfulLogin();

  Future<ReviewPromptStatus> getStatus();

  Future<void> deferPrompt();

  Future<void> completePrompt();
}
