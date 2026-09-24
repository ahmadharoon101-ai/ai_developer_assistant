import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tests_repository.dart';

class TestsController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  Future<void> run({
    required String projectId,
    required String path,
    String symbol = '',
    List<String> kinds = const ['unit'],
    String framework = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(testsRepositoryProvider)
        .generate(projectId: projectId, path: path, symbol: symbol, kinds: kinds, framework: framework));
  }

  void clear() => state = const AsyncData(null);
}

final testsControllerProvider = AsyncNotifierProvider<TestsController, String?>(TestsController.new);
