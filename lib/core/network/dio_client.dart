import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_constants.dart';
import '../errors/failures.dart';
import '../storage/token_storage.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage);
  final TokenStorage _storage;

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.readAccessToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }
}

/// Retries idempotent requests on transient failures with exponential backoff.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.maxRetries = 2});
  final Dio _dio;
  final int maxRetries;

  bool _shouldRetry(DioException e) {
    final idempotent =
        const ['GET', 'HEAD', 'OPTIONS'].contains(e.requestOptions.method);
    final status = e.response?.statusCode ?? 0;
    final transient = e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        (status >= 502 && status <= 504);
    return idempotent && transient;
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra['retry_attempt'] as int?) ?? 0;
    if (!_shouldRetry(err) || attempt >= maxRetries) {
      return handler.next(err);
    }
    await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
    final options = err.requestOptions..extra['retry_attempt'] = attempt + 1;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Signs the user out when the server rejects a previously valid session.
class UnauthorizedInterceptor extends Interceptor {
  UnauthorizedInterceptor(this._onUnauthorized);
  final void Function() _onUnauthorized;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401 &&
        err.requestOptions.headers.containsKey('Authorization')) {
      _onUnauthorized();
    }
    handler.next(err);
  }
}

/// Converts every DioException into one carrying an [ApiException].
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err.copyWith(error: ApiException.fromDio(err)));
  }
}

ApiException toApiException(Object e) {
  if (e is DioException && e.error is ApiException) {
    return e.error as ApiException;
  }
  if (e is ApiException) return e;
  return const ApiException('Something went wrong. Please try again.');
}

/// Set by the auth layer so the network layer can trigger a sign-out
/// without importing it (avoids a circular dependency).
final sessionExpiredProvider =
    StateProvider<void Function()>((ref) => () {});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 120),
    sendTimeout: const Duration(seconds: 60),
    headers: {'Accept': 'application/json'},
  ));
  dio.interceptors.addAll([
    AuthInterceptor(ref.read(tokenStorageProvider)),
    RetryInterceptor(dio),
    UnauthorizedInterceptor(
        () => ref.read(sessionExpiredProvider).call()),
    ErrorInterceptor(),
  ]);
  return dio;
});
