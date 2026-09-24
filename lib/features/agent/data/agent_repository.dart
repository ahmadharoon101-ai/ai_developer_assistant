import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

class AgentStep {
  const AgentStep({required this.stage, required this.title, required this.detail, required this.files});
  final String stage;
  final String title;
  final String detail;
  final List<String> files;

  factory AgentStep.fromJson(Map<String, dynamic> j) => AgentStep(
        stage: j['stage'] as String,
        title: j['title'] as String,
        detail: (j['detail'] as String?) ?? '',
        files: [for (final f in (j['files'] as List?) ?? []) f as String],
      );
}

class AgentPlan {
  const AgentPlan({required this.summary, required this.steps, required this.risks});
  final String summary;
  final List<AgentStep> steps;
  final List<String> risks;
}

class AgentRepository {
  AgentRepository(this._dio);
  final Dio _dio;

  Future<AgentPlan> plan({required String projectId, required String request}) async {
    try {
      final res = await _dio
          .post<dynamic>(ApiConstants.aiAgentPlan, data: {'project_id': projectId, 'request': request});
      final j = res.data as Map<String, dynamic>;
      return AgentPlan(
        summary: j['summary'] as String,
        steps: [for (final s in j['steps'] as List) AgentStep.fromJson(s as Map<String, dynamic>)],
        risks: [for (final r in j['risks'] as List) r as String],
      );
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final agentRepositoryProvider = Provider<AgentRepository>((ref) => AgentRepository(ref.read(dioProvider)));
