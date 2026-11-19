import 'dart:math';

import 'package:dio/dio.dart';

/// Retries transient read failures so a brief network dip does not surface as
/// an error on a TV screen that nobody is sitting in front of.
///
/// Mutating requests are never retried: a duplicate `auth/login` or upload can
/// have side effects. Requests can opt out with `extra: {'skipRetry': true}`.
class ImmichRetryInterceptor extends Interceptor {
  ImmichRetryInterceptor(
    this._dio, {
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 400),
    this.maxDelay = const Duration(seconds: 4),
    this.jitter = 0.25,
    Random? random,
  }) : _random = random ?? Random();

  static const _attemptKey = 'immichRetryAttempt';
  static const _skipRetryKey = 'skipRetry';

  final Dio _dio;
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;
  final double jitter;
  final Random _random;

  /// Pure helper so backoff timing can be unit tested without waiting.
  static Duration computeDelay({
    required int attempt,
    required Duration baseDelay,
    required Duration maxDelay,
    double jitter = 0.25,
    double randomFactor = 0.5,
    int? retryAfterSeconds,
  }) {
    if (retryAfterSeconds != null && retryAfterSeconds >= 0) {
      final retryAfter = Duration(seconds: retryAfterSeconds);
      return retryAfter > maxDelay ? maxDelay : retryAfter;
    }

    final exponential = baseDelay.inMilliseconds * (1 << attempt);
    final capped = min(exponential, maxDelay.inMilliseconds);
    final varied =
        capped + (capped * jitter * randomFactor.clamp(0, 1)).round();
    return Duration(milliseconds: min(varied, maxDelay.inMilliseconds));
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldRetry(err)) {
      handler.next(err);
      return;
    }

    final options = err.requestOptions;
    final attempt = (options.extra[_attemptKey] as int?) ?? 0;
    if (attempt >= maxRetries) {
      handler.next(err);
      return;
    }

    final retryAfter = _parseRetryAfter(
      err.response?.headers.value('retry-after'),
    );
    final delay = computeDelay(
      attempt: attempt,
      baseDelay: baseDelay,
      maxDelay: maxDelay,
      jitter: jitter,
      randomFactor: _random.nextDouble(),
      retryAfterSeconds: retryAfter,
    );

    await Future<void>.delayed(delay);
    if (handler.isCompleted) {
      return;
    }

    options.extra[_attemptKey] = attempt + 1;
    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _shouldRetry(DioException error) {
    final options = error.requestOptions;
    if (options.extra[_skipRetryKey] == true) {
      return false;
    }

    final method = options.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD' && method != 'OPTIONS') {
      return false;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        return statusCode == 408 ||
            statusCode == 429 ||
            (statusCode != null && statusCode >= 500);
      default:
        return false;
    }
  }

  int? _parseRetryAfter(String? value) {
    if (value == null) {
      return null;
    }
    return int.tryParse(value.trim());
  }
}
