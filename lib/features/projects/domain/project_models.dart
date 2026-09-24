class Project {
  const Project({
    required this.id,
    required this.name,
    required this.language,
    required this.framework,
    required this.source,
    required this.githubRepo,
    required this.fileCount,
    required this.lastAnalyzed,
    required this.status,
  });

  final String id;
  final String name;
  final String language;
  final String framework;
  final String source; // empty | zip | github
  final String? githubRepo;
  final int fileCount;
  final String? lastAnalyzed;
  final String status; // Not analyzed | Healthy | Needs review

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        language: (j['language'] as String?) ?? '',
        framework: (j['framework'] as String?) ?? '',
        source: (j['source'] as String?) ?? 'empty',
        githubRepo: j['github_repo'] as String?,
        fileCount: (j['file_count'] as num?)?.toInt() ?? 0,
        lastAnalyzed: j['last_analyzed'] as String?,
        status: (j['status'] as String?) ?? 'Not analyzed',
      );
}

class ProjectFile {
  const ProjectFile({required this.path, required this.size, required this.language});
  final String path;
  final int size;
  final String language;

  String get name => path.split('/').last;

  factory ProjectFile.fromJson(Map<String, dynamic> j) => ProjectFile(
        path: j['path'] as String,
        size: (j['size'] as num).toInt(),
        language: (j['language'] as String?) ?? '',
      );
}
