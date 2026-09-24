import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';

class Issue {
  const Issue({
    required this.title,
    required this.severity,
    required this.category,
    required this.location,
    required this.explanation,
    required this.suggestedFix,
  });
  final String title;
  final String severity; // critical | high | medium | low | info
  final String category;
  final String location;
  final String explanation;
  final String suggestedFix;

  factory Issue.fromJson(Map<String, dynamic> j) => Issue(
        title: j['title'] as String,
        severity: j['severity'] as String,
        category: (j['category'] as String?) ?? '',
        location: (j['location'] as String?) ?? '',
        explanation: (j['explanation'] as String?) ?? '',
        suggestedFix: (j['suggested_fix'] as String?) ?? '',
      );
}

class AnalysisResult {
  const AnalysisResult(
      {required this.summary, required this.complexity, required this.filesAnalyzed, required this.issues});
  final String summary;
  final String complexity;
  final int filesAnalyzed;
  final List<Issue> issues;
}

class AnalyzerRepository {
  AnalyzerRepository(this._dio);
  final Dio _dio;

  Future<AnalysisResult> analyze({
    String? projectId,
    String? path,
    String? code,
    String? language,
    required List<String> focus,
  }) async {
    try {
      final res = await _dio.post<dynamic>(ApiConstants.aiAnalyze, data: {
        'project_id': projectId,
        'path': path,
        'code': code,
        'language': language,
        'focus': focus,
      });
      final j = res.data as Map<String, dynamic>;
      return AnalysisResult(
        summary: j['summary'] as String,
        complexity: (j['complexity'] as String?) ?? '',
        filesAnalyzed: (j['files_analyzed'] as num).toInt(),
        issues: [for (final i in j['issues'] as List) Issue.fromJson(i as Map<String, dynamic>)],
      );
    } catch (e) {
      throw toApiException(e);
    }
  }
}

final analyzerRepositoryProvider =
    Provider<AnalyzerRepository>((ref) => AnalyzerRepository(ref.read(dioProvider)));
