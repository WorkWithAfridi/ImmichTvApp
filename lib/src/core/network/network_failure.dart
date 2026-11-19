import 'package:dio/dio.dart';

import '../errors/app_exception.dart';

/// Distinguishes "the server is unreachable" from "the server said no".
///
/// Only connectivity-style failures should flip the library into its offline
/// mode; auth and permission errors have their own dedicated failure states.
class NetworkFailure {
  const NetworkFailure._();

  static bool isConnectivityIssue(Object? error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        default:
          break;
      }

      final statusCode = error.response?.statusCode;
      return statusCode != null && statusCode >= 500;
    }

    if (error is AppException) {
      return error.code == 'server_unreachable' ||
          error.code == 'network_unavailable';
    }

    return false;
  }
}
