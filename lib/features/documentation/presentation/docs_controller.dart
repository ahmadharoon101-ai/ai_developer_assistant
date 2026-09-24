import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/docs_repository.dart';

class DocsController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  Future<void> run({required String projectId, required String docType, String? path}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(docsRepositoryProvider).generate(projectId: projectId, docType: docType, path: path));
  }

  void setContent(String text) => state = AsyncData(text);
  void clear() => state = const AsyncData(null);
}

final docsControllerProvider = AsyncNotifierProvider<DocsController, String?>(DocsController.new);
