import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/panel.dart';
import '../../projects/domain/project_models.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../data/dashboard_repository.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final _command = TextEditingController();

  static const _prompts = [
    'Explain my project',
    'Find bugs in my code',
    'Generate a FastAPI endpoint',
    'Write tests for this function',
    'Explain this error',
    'Review my code',
  ];

  static const _actions = [
    (Icons.forum_outlined, 'Ask AI', 'Chat about your code', '/chat'),
    (Icons.manage_search, 'Analyze Project', 'Find issues and smells', '/analyzer'),
    (Icons.bug_report_outlined, 'Debug Error', 'Paste a stack trace', '/debugger'),
    (Icons.code, 'Generate Code', 'Functions, APIs, models', '/generator'),
    (Icons.fact_check_outlined, 'Generate Tests', 'Unit, API, edge cases', '/tests'),
    (Icons.description_outlined, 'Create Documentation', 'README and guides', '/docs'),
  ];

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  void _ask(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    ref.read(chatControllerProvider.notifier).startWith(t);
    _command.clear();
    context.go('/chat');
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning'
        : h < 18
            ? 'Good afternoon'
            : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final user = ref.watch(authControllerProvider).valueOrNull;
    final first = (user?.name.split(' ').first ?? '').trim();
    final data = ref.watch(dashboardProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_greeting()}, ${first.isEmpty ? 'Developer' : first} 👋',
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('What would you like to build today?',
                  style: t.bodyLarge?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 22),
              Panel(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('>', style: AppTheme.mono(size: 18, color: AppColors.accent)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _command,
                          onSubmitted: _ask,
                          style: const TextStyle(fontSize: 16),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Ask your AI Developer Assistant…',
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: () => _ask(_command.text),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in _prompts)
                          ActionChip(
                            label: Text(p),
                            backgroundColor: AppColors.surfaceHigh,
                            side: BorderSide(color: AppColors.border),
                            onPressed: () => _ask(p),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text('Quick actions',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ResponsiveGrid(minItemWidth: 260, children: [
                for (final a in _actions)
                  Panel(
                    onTap: () => context.go(a.$4),
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(a.$1, color: AppColors.accent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.$2,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(a.$3,
                                style: t.bodySmall?.copyWith(color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ]),
                  ),
              ]),
              const SizedBox(height: 28),
              data.when(
                loading: () => const _DashboardSkeleton(),
                error: (e, _) =>
                    ErrorPanel(error: e, onRetry: () => ref.invalidate(dashboardProvider)),
                data: (d) => _DashboardBody(d),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody(this.d);
  final DashboardData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final stats = [
      ('Projects', d.projects, Icons.folder_copy_outlined),
      ('AI Conversations', d.conversations, Icons.forum_outlined),
      ('Files Analyzed', d.filesAnalyzed, Icons.article_outlined),
      ('Bugs Detected', d.bugsDetected, Icons.bug_report_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveGrid(minItemWidth: 200, children: [
          for (final s in stats)
            Panel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(s.$3, size: 18, color: AppColors.muted),
                  const SizedBox(height: 10),
                  Text('${s.$2}',
                      style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(s.$1, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
            child: Text('Recent projects',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: () => context.go('/projects'), child: const Text('View all')),
        ]),
        const SizedBox(height: 8),
        Panel(
          padding: EdgeInsets.zero,
          child: d.recentProjects.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_open,
                  title: 'No projects yet',
                  message: 'Upload a ZIP or import a GitHub repository to get started.')
              : Column(children: [
                  for (var i = 0; i < d.recentProjects.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _ProjectRow(d.recentProjects[i]),
                  ],
                ]),
        ),
        const SizedBox(height: 28),
        Text('Recent conversations',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Panel(
          padding: EdgeInsets.zero,
          child: d.recentConversations.isEmpty
              ? const EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  message: 'Ask your first question in the box above.')
              : Column(children: [
                  for (var i = 0; i < d.recentConversations.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.forum_outlined, color: AppColors.muted),
                      title: Text(d.recentConversations[i].title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(d.recentConversations[i].updated,
                          style: t.bodySmall?.copyWith(color: AppColors.muted)),
                      onTap: () {
                        ref
                            .read(chatControllerProvider.notifier)
                            .select(d.recentConversations[i].id);
                        context.go('/chat');
                      },
                    ),
                  ],
                ]),
        ),
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow(this.p);
  final Project p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: Icon(Icons.folder_outlined, color: AppColors.muted),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          if (p.language.isNotEmpty) p.language,
          if (p.framework.isNotEmpty) p.framework,
          '${p.fileCount} files',
          'analyzed ${p.lastAnalyzed == null ? 'never' : relativeTime(p.lastAnalyzed)}',
        ].join(' · '),
        style: t.bodySmall?.copyWith(color: AppColors.muted),
      ),
      trailing: StatusChip(p.status),
      onTap: () => context.go('/projects/${p.id}'),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveGrid(minItemWidth: 200, children: [
          for (var i = 0; i < 4; i++)
            const Panel(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 18, height: 18),
                  SizedBox(height: 12),
                  SkeletonBox(width: 60, height: 28),
                  SizedBox(height: 8),
                  SkeletonBox(width: 110, height: 12),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 28),
        const Panel(
          child: Column(children: [
            SkeletonBox(height: 16),
            SizedBox(height: 18),
            SkeletonBox(height: 16),
            SizedBox(height: 18),
            SkeletonBox(height: 16),
          ]),
        ),
      ],
    );
  }
}
