import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../domain/project_models.dart';

class ProjectsRepository {
  ProjectsRepository(this._dio);
  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw toApiException(e);
    }
  }

  Future<List<Project>> list() => _guard(() async {
        final res = await _dio.get<dynamic>(ApiConstants.projects);
        return [for (final p in res.data as List) Project.fromJson(p as Map<String, dynamic>)];
      });

  Future<Project> create(String name, {String language = '', String framework = ''}) =>
      _guard(() async {
        final res = await _dio.post<dynamic>(ApiConstants.projects,
            data: {'name': name, 'language': language, 'framework': framework});
        return Project.fromJson(res.data as Map<String, dynamic>);
      });

  Future<Project> upload(List<int> bytes, String filename, {String name = ''}) =>
      _guard(() async {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: filename),
          if (name.isNotEmpty) 'name': name,
        });
        final res = await _dio.post<dynamic>(ApiConstants.projectUpload, data: form);
        return Project.fromJson(res.data as Map<String, dynamic>);
      });

  Future<Project> importGithub(String repo, {String ref = ''}) => _guard(() async {
        final res = await _dio.post<dynamic>(ApiConstants.projectImportGithub,
            data: {'repo': repo, 'ref': ref});
        return Project.fromJson(res.data as Map<String, dynamic>);
      });

  Future<void> delete(String id) =>
      _guard(() => _dio.delete<dynamic>('${ApiConstants.projects}/$id'));

  Future<List<ProjectFile>> files(String id) => _guard(() async {
        final res = await _dio.get<dynamic>('${ApiConstants.projects}/$id/files');
        return [for (final f in res.data as List) ProjectFile.fromJson(f as Map<String, dynamic>)];
      });

  Future<String> fileContent(String id, String path) => _guard(() async {
        final res = await _dio.get<dynamic>('${ApiConstants.projects}/$id/files/content',
            queryParameters: {'path': path});
        return (res.data as Map<String, dynamic>)['content'] as String;
      });

  Future<void> writeFile(String id, String path, String content) => _guard(() =>
      _dio.put<dynamic>('${ApiConstants.projects}/$id/files/content',
          data: {'path': path, 'content': content}));
}
