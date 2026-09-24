import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/data/dashboard_repository.dart';
import '../../projects/presentation/projects_controller.dart';
import '../data/analyzer_repository.dart';

class AnalyzerController extends AsyncNotifier<AnalysisResult?> {
  @override
  Future<AnalysisResult?> build() async => null;

  Future<void> run({
    String? projectId,
    String? path,
    String? code,
    String? language,
    required List<String> focus,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(analyzerRepositoryProvider).analyze(
        projectId: projectId, path: path, code: code, language: language, focus: focus));
    // Project health and dashboard counters changed on the server.
    ref.invalidate(projectsProvider);
    ref.invalidate(dashboardProvider);
  }

  void clear() => state = const AsyncData(null);
}

final analyzerControllerProvider =
    AsyncNotifierProvider<AnalyzerController, AnalysisResult?>(AnalyzerController.new);
