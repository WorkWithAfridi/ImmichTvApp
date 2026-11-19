import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/network/immich_retry_interceptor.dart';

void main() {
  group('computeDelay', () {
    test('grows exponentially and respects the cap', () {
      final delay = ImmichRetryInterceptor.computeDelay(
        attempt: 0,
        baseDelay: const Duration(milliseconds: 400),
        maxDelay: const Duration(seconds: 4),
        jitter: 0,
      );
      final larger = ImmichRetryInterceptor.computeDelay(
        attempt: 1,
        baseDelay: const Duration(milliseconds: 400),
        maxDelay: const Duration(seconds: 4),
        jitter: 0,
      );
      final capped = ImmichRetryInterceptor.computeDelay(
        attempt: 10,
        baseDelay: const Duration(milliseconds: 400),
        maxDelay: const Duration(seconds: 4),
        jitter: 0,
      );

      expect(delay, const Duration(milliseconds: 400));
      expect(larger, const Duration(milliseconds: 800));
      expect(capped, const Duration(seconds: 4));
    });

    test('honors Retry-After and adds bounded jitter', () {
      final retryAfter = ImmichRetryInterceptor.computeDelay(
        attempt: 3,
        baseDelay: const Duration(milliseconds: 100),
        maxDelay: const Duration(seconds: 10),
        retryAfterSeconds: 2,
      );
      final jittered = ImmichRetryInterceptor.computeDelay(
        attempt: 0,
        baseDelay: const Duration(milliseconds: 1000),
        maxDelay: const Duration(seconds: 10),
        jitter: 0.25,
        randomFactor: 1,
      );

      expect(retryAfter, const Duration(seconds: 2));
      expect(jittered, const Duration(milliseconds: 1250));
    });
  });

  test('retries a failing GET and resolves with the second response', () async {
    final dio = Dio();
    final adapter = _FlakyAdapter(failuresRemaining: 1);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      ImmichRetryInterceptor(
        dio,
        baseDelay: Duration.zero,
        maxDelay: Duration.zero,
        random: Random(1),
      ),
    );

    final response = await dio.get<String>('https://example.test/api/albums');

    expect(response.statusCode, 200);
    expect(response.data, 'ok');
    expect(adapter.requestCount, 2);
  });

  test('gives up after maxRetries', () async {
    final dio = Dio();
    final adapter = _FlakyAdapter(failuresRemaining: 5);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      ImmichRetryInterceptor(
        dio,
        maxRetries: 2,
        baseDelay: Duration.zero,
        maxDelay: Duration.zero,
      ),
    );

    await expectLater(
      dio.get<String>('https://example.test/api/albums'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requestCount, 3);
  });

  test('never retries POST or opted-out requests', () async {
    final dio = Dio();
    final adapter = _FlakyAdapter(failuresRemaining: 5);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      ImmichRetryInterceptor(
        dio,
        baseDelay: Duration.zero,
        maxDelay: Duration.zero,
      ),
    );

    await expectLater(
      dio.post<String>('https://example.test/api/auth/login'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      dio.get<String>(
        'https://example.test/api/albums',
        options: Options(extra: const {'skipRetry': true}),
      ),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requestCount, 2);
  });
}

class _FlakyAdapter implements HttpClientAdapter {
  _FlakyAdapter({required this.failuresRemaining});

  int failuresRemaining;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount += 1;
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'connection refused',
      );
    }
    return ResponseBody.fromString('ok', 200);
  }

  @override
  void close({bool force = false}) {}
}
