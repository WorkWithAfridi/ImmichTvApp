import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/errors/app_exception.dart';
import 'package:immichtv/src/core/network/image_retry_policy.dart';

void main() {
  const policy = ImageRetryPolicy();

  test('retries transient failures within the configured budget', () {
    final connectionError = DioException.connectionError(
      requestOptions: RequestOptions(path: '/thumbnail'),
      reason: 'connection reset',
    );

    expect(policy.shouldRetry(0, connectionError), isTrue);
    expect(policy.shouldRetry(1, connectionError), isTrue);
    expect(policy.shouldRetry(2, connectionError), isFalse);
  });

  test('does not retry permission or missing-asset errors', () {
    final forbidden = DioException(
      requestOptions: RequestOptions(path: '/thumbnail'),
      type: DioExceptionType.badResponse,
      response: Response<int>(
        requestOptions: RequestOptions(path: '/thumbnail'),
        statusCode: 403,
      ),
    );

    expect(policy.shouldRetry(0, forbidden), isFalse);
    expect(
      policy.shouldRetry(
        0,
        const AppException('missing', code: 'asset_not_found'),
      ),
      isFalse,
    );
  });

  test('retries empty payloads', () {
    expect(
      policy.shouldRetry(0, const FormatException('No image bytes')),
      isTrue,
    );
  });

  test('delay is bounded', () {
    expect(
      policy.delayFor(10),
      lessThanOrEqualTo(const Duration(seconds: 2)),
    );
  });
}
