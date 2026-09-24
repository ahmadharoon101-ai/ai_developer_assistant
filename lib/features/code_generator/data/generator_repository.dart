import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

class GeneratorRepository {
  GeneratorRepository(this._dio);
  final Dio _dio;

  Future<String> generate({
    required String mode, // generate | improve | explain
    required String language,
    String framework = '',
    String kind = '',
    String prompt = '',
    String code = '',
  }) async {
    try {
      final res = await _dio.post<dynamic>(ApiConstants.aiGenerate, data: {
        'mode': mode,
        'language': language,
        'framework': framework,
        'kind': kind,
        'prompt': prompt,
        'code': code,
      });
      return (res.data as Map<String, dynamic>)['content'] as String;
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final generatorRepositoryProvider =
    Provider<GeneratorRepository>((ref) => GeneratorRepository(ref.read(dioProvider)));
