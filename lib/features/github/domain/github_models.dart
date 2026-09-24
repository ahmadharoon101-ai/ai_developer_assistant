class GithubStatus {
  const GithubStatus({required this.connected, required this.login, required this.oauthAvailable});
  final bool connected;
  final String? login;
  final bool oauthAvailable;

  factory GithubStatus.fromJson(Map<String, dynamic> j) => GithubStatus(
        connected: j['connected'] as bool,
        login: j['login'] as String?,
        oauthAvailable: j['oauth_available'] as bool,
      );
}

class GithubRepo {
  const GithubRepo({
    required this.fullName,
    required this.description,
    required this.language,
    required this.isPrivate,
    required this.updatedAt,
    required this.defaultBranch,
    required this.stars,
  });
  final String fullName;
  final String description;
  final String language;
  final bool isPrivate;
  final String updatedAt;
  final String defaultBranch;
  final int stars;

  factory GithubRepo.fromJson(Map<String, dynamic> j) => GithubRepo(
        fullName: j['full_name'] as String,
        description: (j['description'] as String?) ?? '',
        language: (j['language'] as String?) ?? '',
        isPrivate: j['private'] as bool,
        updatedAt: j['updated_at'] as String,
        defaultBranch: j['default_branch'] as String,
        stars: (j['stars'] as num?)?.toInt() ?? 0,
      );
}
