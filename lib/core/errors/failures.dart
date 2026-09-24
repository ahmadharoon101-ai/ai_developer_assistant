import 'package:dio/dio.dart';

/// Single error type the UI ever sees from the network layer.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
            'The server took too long to respond. Check your connection and try again.');
      case DioExceptionType.connectionError:
        return const ApiException(
            'Could not reach the server. Check your connection and try again.');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return ApiException(_detail(e.response?.data) ?? _byStatus(code),
            statusCode: code);
      case DioExceptionType.cancel:
        return const ApiException('The request was cancelled.');
      default:
        return const ApiException('Something went wrong. Please try again.');
    }
  }

  /// FastAPI returns {"detail": "..."} or {"detail": [{"msg": "..."}]}.
  static String? _detail(dynamic data) {
    if (data is Map && data['detail'] != null) {
      final d = data['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty && d.first is Map) {
        return (d.first as Map)['msg']?.toString();
      }
    }
    return null;
  }

  static String _byStatus(int? code) {
    switch (code) {
      case 401:
        return 'Incorrect email or password.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'We could not find what you asked for.';
      case 413:
        return 'That file is too large.';
      case 429:
        return 'Too many requests. Wait a moment and try again.';
      default:
        return 'The server returned an error ($code).';
    }
  }

  @override
  String toString() => message;
}
