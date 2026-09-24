import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/time_utils.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../chat/domain/chat_models.dart';
import '../../projects/domain/project_models.dart';

class DashboardData {
  const DashboardData({
    required this.projects,
    required this.conversations,
    required this.filesAnalyzed,
    required this.bugsDetected,
    required this.recentConversations,
    required this.recentProjects,
  });
  final int projects;
  final int conversations;
  final int filesAnalyzed;
  final int bugsDetected;
  final List<Conversation> recentConversations;
  final List<Project> recentProjects;
}

class DashboardRepository {
  DashboardRepository(this._dio);
  final Dio _dio;

  Future<DashboardData> load() async {
    try {
      final res = await _dio.get<dynamic>(ApiConstants.dashboard);
      final j = res.data as Map<String, dynamic>;
      return DashboardData(
        projects: (j['projects'] as num).toInt(),
        conversations: (j['conversations'] as num).toInt(),
        filesAnalyzed: (j['files_analyzed'] as num).toInt(),
        bugsDetected: (j['bugs_detected'] as num).toInt(),
        recentConversations: [
          for (final c in j['recent_conversations'] as List)
            Conversation(
                id: c['id'] as String,
                title: c['title'] as String,
                updated: relativeTime(c['updated_at'] as String?))
        ],
        recentProjects: [
          for (final p in j['recent_projects'] as List) Project.fromJson(p as Map<String, dynamic>)
        ],
      );
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) {
  ref.watch(authControllerProvider.select((a) => a.valueOrNull?.id));
  return DashboardRepository(ref.read(dioProvider)).load();
});
