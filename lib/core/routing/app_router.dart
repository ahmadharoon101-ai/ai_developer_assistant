import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/agent/presentation/agent_page.dart';
import '../../features/analyzer/presentation/analyzer_page.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/chat/presentation/chat_page.dart';
import '../../features/code_generator/presentation/generator_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/debugger/presentation/debugger_page.dart';
import '../../features/documentation/presentation/docs_page.dart';
import '../../features/github/presentation/github_page.dart';
import '../../features/projects/presentation/project_explorer_page.dart';
import '../../features/projects/presentation/projects_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../features/test_generator/presentation/tests_page.dart';
import '../../shared/widgets/app_shell.dart';

Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 160),
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      if (auth.isLoading) return loc == '/splash' ? null : '/splash';
      final loggedIn = auth.valueOrNull != null;
      const publicRoutes = {'/login', '/register'};
      if (loc == '/splash') return loggedIn ? '/dashboard' : '/login';
      if (!loggedIn && !publicRoutes.contains(loc)) return '/login';
      if (loggedIn && publicRoutes.contains(loc)) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', pageBuilder: (_, s) => _fade(s, const DashboardPage())),
          GoRoute(path: '/chat', pageBuilder: (_, s) => _fade(s, const ChatPage())),
          GoRoute(path: '/settings', pageBuilder: (_, s) => _fade(s, const SettingsPage())),
          GoRoute(path: '/github', pageBuilder: (_, s) => _fade(s, const GithubPage())),
          GoRoute(
            path: '/projects',
            pageBuilder: (_, s) => _fade(s, const ProjectsPage()),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, s) =>
                    _fade(s, ProjectExplorerPage(projectId: s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/analyzer',
            pageBuilder: (_, s) => _fade(
              s,
              AnalyzerPage(
                projectId: s.uri.queryParameters['project'],
                path: s.uri.queryParameters['path'],
              ),
            ),
          ),
          GoRoute(path: '/debugger', pageBuilder: (_, s) => _fade(s, const DebuggerPage())),
          GoRoute(path: '/generator', pageBuilder: (_, s) => _fade(s, const GeneratorPage())),
          GoRoute(
            path: '/tests',
            pageBuilder: (_, s) => _fade(
              s,
              TestsPage(
                projectId: s.uri.queryParameters['project'],
                path: s.uri.queryParameters['path'],
              ),
            ),
          ),
          GoRoute(
            path: '/docs',
            pageBuilder: (_, s) => _fade(s, DocsPage(projectId: s.uri.queryParameters['project'])),
          ),
          GoRoute(
            path: '/agent',
            pageBuilder: (_, s) => _fade(s, AgentPage(projectId: s.uri.queryParameters['project'])),
          ),
        ],
      ),
    ],
  );
});
