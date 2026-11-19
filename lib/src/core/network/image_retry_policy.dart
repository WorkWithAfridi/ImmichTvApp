import 'package:flutter/foundation.dart';

import 'immich_retry_interceptor.dart';
import 'network_failure.dart';

/// Bounded retry policy for thumbnail and fullscreen image loads.
///
/// A failed image is retried on the same URL a small number of times before
/// the widget advances to its next fallback URL. Only transient failures are
/// retried; auth/permission errors move on immediately.
class ImageRetryPolicy {
  const ImageRetryPolicy({
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 300),
    this.maxDelay = const Duration(seconds: 2),
  });

  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;

  bool shouldRetry(int attempt, Object error) {
    return attempt < maxRetries && isRetryable(error);
  }

  Duration delayFor(int attempt) {
    return ImmichRetryInterceptor.computeDelay(
      attempt: attempt,
      baseDelay: baseDelay,
      maxDelay: maxDelay,
      jitter: 0.2,
      randomFactor: 0.5,
    );
  }

  static bool isRetryable(Object error) {
    if (NetworkFailure.isConnectivityIssue(error)) {
      return true;
    }
    if (error is FormatException) {
      return true;
    }
    if (kIsWeb && error.toString().toLowerCase().contains('network')) {
      return true;
    }
    return false;
  }
}
