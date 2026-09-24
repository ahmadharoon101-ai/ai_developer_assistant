import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

class DebugResult {
  const DebugResult({
    required this.problem,
    required this.cause,
    required this.solution,
    required this.explanation,
    required this.fixCode,
    required this.fixLanguage,
  });
  final String problem;
  final String cause;
  final String solution;
  final String explanation;
  final String fixCode;
  final String fixLanguage;

  factory DebugResult.fromJson(Map<String, dynamic> j) => DebugResult(
        problem: j['problem'] as String,
        cause: j['cause'] as String,
        solution: j['solution'] as String,
        explanation: j['explanation'] as String,
        fixCode: (j['fix_code'] as String?) ?? '',
        fixLanguage: (j['fix_language'] as String?) ?? '',
      );
}

class DebuggerRepository {
  DebuggerRepository(this._dio);
  final Dio _dio;

  Future<DebugResult> debug({
    required String error,
    String stackTrace = '',
    String code = '',
    String language = '',
  }) async {
    try {
      final res = await _dio.post<dynamic>(ApiConstants.aiDebug, data: {
        'error': error,
        'stack_trace': stackTrace,
        'code': code,
        'language': language,
      });
      return DebugResult.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final debuggerRepositoryProvider =
    Provider<DebuggerRepository>((ref) => DebuggerRepository(ref.read(dioProvider)));
