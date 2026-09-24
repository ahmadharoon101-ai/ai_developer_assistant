import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';

class SavedItem {
  const SavedItem({required this.id, required this.title, required this.createdAt, required this.payload});
  final int id;
  final String title;
  final String createdAt;
  final Map<String, dynamic> payload;
}

class SavedRepository {
  SavedRepository(this._dio);
  final Dio _dio;

  Future<List<SavedItem>> list(String kind) async {
    try {
      final res = await _dio.get<dynamic>(ApiConstants.saved, queryParameters: {'kind': kind});
      return [
        for (final j in res.data as List)
          SavedItem(
            id: (j['id'] as num).toInt(),
            title: j['title'] as String,
            createdAt: j['created_at'] as String,
            payload: Map<String, dynamic>.from(j['payload'] as Map),
          )
      ];
    } catch (e) {
      throw toApiException(e);
    }
  }

  Future<void> save(String kind, String title, Map<String, dynamic> payload) async {
    try {
      await _dio.post<dynamic>(ApiConstants.saved,
          data: {'kind': kind, 'title': title, 'payload': payload});
    } catch (e) {
      throw toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete<dynamic>('${ApiConstants.saved}/$id');
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final savedRepositoryProvider =
    Provider<SavedRepository>((ref) => SavedRepository(ref.read(dioProvider)));
