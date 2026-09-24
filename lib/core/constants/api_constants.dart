import 'package:flutter/foundation.dart';

/// Backend address. Override at build time:
///   flutter run --dart-define=API_BASE_URL=https://api.yourdomain.com
/// Physical phone on your Wi-Fi: use your computer's LAN IP, e.g. http://192.168.1.20:8000
/// No secrets live in the app: AI keys and GitHub tokens stay on the FastAPI backend.
class ApiConstants {
  const ApiConstants._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override.replaceAll(RegExp(r'/+$'), '');
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000'; // Android emulator -> host machine
    }
    return 'http://localhost:8000';
  }

  static String get wsUrl {
    final u = Uri.parse(baseUrl);
    return u
        .replace(scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '${u.path}/ws/chat')
        .toString();
  }

  static const login = '/auth/login';
  static const register = '/auth/register';
  static const me = '/auth/me';
  static const forgotPassword = '/auth/forgot-password';
  static const resetPassword = '/auth/reset-password';
  static const profile = '/auth/profile';
  static const password = '/auth/password';
  static const logoutAll = '/auth/logout-all';
  static const conversations = '/conversations';
  static const dashboard = '/dashboard/stats';
  static const projects = '/projects';
  static const projectUpload = '/projects/upload';
  static const projectImportGithub = '/projects/import-github';
  static const aiAnalyze = '/ai/analyze';
  static const aiDebug = '/ai/debug';
  static const aiGenerate = '/ai/generate';
  static const aiTests = '/ai/tests';
  static const aiDocumentation = '/ai/documentation';
  static const aiAgentPlan = '/ai/agent/plan';
  static const settings = '/settings';
  static const saved = '/saved';
  static const health = '/health';
  static const githubStatus = '/github/status';
  static const githubOauthStart = '/github/oauth/start';
  static const githubToken = '/github/token';
  static const githubConnection = '/github/connection';
  static const githubRepositories = '/github/repositories';
  static const githubPrDescription = '/github/pr-description';
}
