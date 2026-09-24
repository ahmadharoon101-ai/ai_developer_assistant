import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/agent_repository.dart';

class AgentController extends AsyncNotifier<AgentPlan?> {
  @override
  Future<AgentPlan?> build() async => null;

  Future<void> plan({required String projectId, required String request}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(agentRepositoryProvider).plan(projectId: projectId, request: request));
  }

  void clear() => state = const AsyncData(null);
}

final agentControllerProvider = AsyncNotifierProvider<AgentController, AgentPlan?>(AgentController.new);
