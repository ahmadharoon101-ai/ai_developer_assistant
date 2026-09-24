import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/projects_repository.dart';
import '../domain/project_models.dart';

final projectsRepositoryProvider =
    Provider<ProjectsRepository>((ref) => ProjectsRepository(ref.read(dioProvider)));

/// All of the signed-in user's projects. Errors are ApiException.
class ProjectsController extends AsyncNotifier<List<Project>> {
  ProjectsRepository get _repo => ref.read(projectsRepositoryProvider);

  @override
  Future<List<Project>> build() {
    ref.watch(authControllerProvider.select((a) => a.valueOrNull?.id));
    return _repo.list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<Project>>().copyWithPrevious(state);
    state = await AsyncValue.guard(_repo.list);
  }

  Future<Project> create(String name, {String language = '', String framework = ''}) async {
    final p = await _repo.create(name, language: language, framework: framework);
    await refresh();
    return p;
  }

  Future<Project> upload(List<int> bytes, String filename, {String name = ''}) async {
    final p = await _repo.upload(bytes, filename, name: name);
    await refresh();
    return p;
  }

  Future<Project> importGithub(String repo, {String ref = ''}) async {
    final p = await _repo.importGithub(repo, ref: ref);
    await refresh();
    return p;
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await refresh();
  }
}

final projectsProvider =
    AsyncNotifierProvider<ProjectsController, List<Project>>(ProjectsController.new);

final projectFilesProvider =
    FutureProvider.autoDispose.family<List<ProjectFile>, String>(
        (ref, id) => ref.read(projectsRepositoryProvider).files(id));

typedef FileKey = ({String id, String path});

final fileContentProvider = FutureProvider.autoDispose.family<String, FileKey>(
    (ref, k) => ref.read(projectsRepositoryProvider).fileContent(k.id, k.path));
