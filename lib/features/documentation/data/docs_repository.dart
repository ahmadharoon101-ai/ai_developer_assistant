import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

class DocsRepository {
  DocsRepository(this._dio);
  final Dio _dio;

  Future<String> generate({required String projectId, required String docType, String? path}) async {
    try {
      final res = await _dio.post<dynamic>(ApiConstants.aiDocumentation,
          data: {'project_id': projectId, 'doc_type': docType, 'path': path});
      return (res.data as Map<String, dynamic>)['content'] as String;
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final docsRepositoryProvider = Provider<DocsRepository>((ref) => DocsRepository(ref.read(dioProvider)));
