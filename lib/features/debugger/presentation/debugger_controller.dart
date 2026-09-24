import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/debugger_repository.dart';

class DebuggerController extends AsyncNotifier<DebugResult?> {
  @override
  Future<DebugResult?> build() async => null;

  Future<void> run({required String error, String stackTrace = '', String code = '', String language = ''}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(debuggerRepositoryProvider)
        .debug(error: error, stackTrace: stackTrace, code: code, language: language));
  }

  void setResult(DebugResult r) => state = AsyncData(r);
  void clear() => state = const AsyncData(null);
}

final debuggerControllerProvider =
    AsyncNotifierProvider<DebuggerController, DebugResult?>(DebuggerController.new);
