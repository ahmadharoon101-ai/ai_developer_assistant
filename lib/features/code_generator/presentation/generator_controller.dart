import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/generator_repository.dart';

class GeneratorController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  Future<void> run({
    required String mode,
    required String language,
    String framework = '',
    String kind = '',
    String prompt = '',
    String code = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(generatorRepositoryProvider).generate(
        mode: mode, language: language, framework: framework, kind: kind, prompt: prompt, code: code));
  }

  void setResult(String text) => state = AsyncData(text);
  void clear() => state = const AsyncData(null);
}

final generatorControllerProvider =
    AsyncNotifierProvider<GeneratorController, String?>(GeneratorController.new);
