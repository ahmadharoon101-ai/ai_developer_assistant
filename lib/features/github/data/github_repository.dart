import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../domain/github_models.dart';

class GithubRepository {
  GithubRepository(this._dio);
  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw toApiException(e);
    }
  }

  Future<GithubStatus> status() => _guard(() async {
        final res = await _dio.get<dynamic>(ApiConstants.githubStatus);
        return GithubStatus.fromJson(res.data as Map<String, dynamic>);
      });

  Future<String> oauthStartUrl() => _guard(() async {
        final res = await _dio.get<dynamic>(ApiConstants.githubOauthStart);
        return (res.data as Map<String, dynamic>)['url'] as String;
      });

  Future<String> connectWithToken(String token) => _guard(() async {
        final res = await _dio.post<dynamic>(ApiConstants.githubToken, data: {'token': token});
        return (res.data as Map<String, dynamic>)['login'] as String;
      });

  Future<void> disconnect() => _guard(() => _dio.delete<dynamic>(ApiConstants.githubConnection));

  Future<List<GithubRepo>> repositories() => _guard(() async {
        final res = await _dio.get<dynamic>(ApiConstants.githubRepositories);
        return [for (final r in res.data as List) GithubRepo.fromJson(r as Map<String, dynamic>)];
      });

  Future<String> prDescription({required String repo, required String base, required String head}) =>
      _guard(() async {
        final res = await _dio
            .post<dynamic>(ApiConstants.githubPrDescription, data: {'repo': repo, 'base': base, 'head': head});
        return (res.data as Map<String, dynamic>)['content'] as String;
      });
}

final githubRepositoryProvider = Provider<GithubRepository>((ref) => GithubRepository(ref.read(dioProvider)));

final githubStatusProvider =
    FutureProvider.autoDispose<GithubStatus>((ref) => ref.read(githubRepositoryProvider).status());

final githubReposProvider =
    FutureProvider.autoDispose<List<GithubRepo>>((ref) => ref.read(githubRepositoryProvider).repositories());
