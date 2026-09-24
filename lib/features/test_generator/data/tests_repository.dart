import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

class TestsRepository {
  TestsRepository(this._dio);
  final Dio _dio;

  Future<String> generate({
    required String projectId,
    required String path,
    String symbol = '',
    List<String> kinds = const ['unit'],
    String framework = '',
  }) async {
    try {
      final res = await _dio.post<dynamic>(ApiConstants.aiTests, data: {
        'project_id': projectId,
        'path': path,
        'symbol': symbol,
        'kinds': kinds,
        'framework': framework,
      });
      return (res.data as Map<String, dynamic>)['content'] as String;
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final testsRepositoryProvider = Provider<TestsRepository>((ref) => TestsRepository(ref.read(dioProvider)));
