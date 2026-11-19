import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/errors/app_exception.dart';
import 'package:immichtv/src/core/network/network_failure.dart';

void main() {
  test('connection and timeout errors count as connectivity issues', () {
    for (final type in <DioExceptionType>[
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ]) {
      expect(
        NetworkFailure.isConnectivityIssue(
          DioException(requestOptions: RequestOptions(path: '/x'), type: type),
        ),
        isTrue,
        reason: '$type should be treated as offline',
      );
    }
  });

  test('5xx responses count as connectivity issues', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response<String>(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 503,
      ),
    );

    expect(NetworkFailure.isConnectivityIssue(error), isTrue);
  });

  test('auth and permission errors do not count as connectivity issues', () {
    for (final statusCode in <int>[401, 403, 404]) {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response<String>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: statusCode,
        ),
      );
      expect(NetworkFailure.isConnectivityIssue(error), isFalse);
    }
  });

  test('server validation exception counts as connectivity issue', () {
    expect(
      NetworkFailure.isConnectivityIssue(
        const AppException('unreachable', code: 'server_unreachable'),
      ),
      isTrue,
    );
    expect(
      NetworkFailure.isConnectivityIssue(
        const AppException('bad key', code: 'invalid_api_key'),
      ),
      isFalse,
    );
  });
}
