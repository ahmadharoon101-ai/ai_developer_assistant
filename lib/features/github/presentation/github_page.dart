import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/failures.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/components/rich_content.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/widgets/search_field.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../projects/presentation/projects_controller.dart';
import '../data/github_repository.dart';
import '../domain/github_models.dart';

class GithubPage extends ConsumerStatefulWidget {
  const GithubPage({super.key});

  @override
  ConsumerState<GithubPage> createState() => _GithubPageState();
}

class _GithubPageState extends ConsumerState<GithubPage> {
  String _query = '';

  Future<void> _connectWithToken() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Connect with a personal access token'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Create a fine-grained token with read access to repository contents at '
                'github.com/settings/tokens, then paste it here. It is encrypted on the server and never sent back to this app.',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(controller: controller, obscureText: true, decoration: fieldDecoration('Token')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Connect')),
        ],
      ),
    );
    if (ok != true || controller.text.trim().isEmpty) return;
    try {
      final login = await ref.read(githubRepositoryProvider).connectWithToken(controller.text.trim());
      ref.invalidate(githubStatusProvider);
      ref.invalidate(githubReposProvider);
      if (mounted) showToast(context, 'Connected as $login');
    } catch (e) {
      if (mounted) showToast(context, toApiException(e).message);
    }
  }

  Future<void> _connectOAuth() async {
    try {
      final url = await ref.read(githubRepositoryProvider).oauthStartUrl();
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showToast(context, 'Could not open the browser.');
    } catch (e) {
      if (mounted) showToast(context, toApiException(e).message);
    }
  }

  Future<void> _disconnect() async {
    try {
      await ref.read(githubRepositoryProvider).disconnect();
      ref.invalidate(githubStatusProvider);
      if (mounted) showToast(context, 'GitHub disconnected');
    } catch (e) {
      if (mounted) showToast(context, toApiException(e).message);
    }
  }

  Future<void> _import(GithubRepo repo) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 18),
          Expanded(child: Text('Importing ${repo.fullName}…')),
        ]),
      ),
    );
    try {
      final p = await ref.read(projectsProvider.notifier).importGithub(repo.fullName, ref: repo.defaultBranch);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, '"${p.name}" imported (${p.fileCount} files)');
      context.go('/projects/${p.id}');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, toApiException(e).message);
    }
  }

  Future<void> _askAboutRepo(GithubRepo repo) async {
    await ref
        .read(chatControllerProvider.notifier)
        .startWith('Tell me about the GitHub repository ${repo.fullName}. What does it look like it does, '
            'based on its description and language (${repo.language})?');
    if (mounted) context.go('/chat');
  }

  Future<void> _generateReadme(GithubRepo repo) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: Row(children: const [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 18),
          Expanded(child: Text('Importing repository to generate a README…')),
        ]),
      ),
    );
    try {
      final p = await ref.read(projectsProvider.notifier).importGithub(repo.fullName, ref: repo.defaultBranch);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      context.go('/docs?project=${p.id}');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, toApiException(e).message);
    }
  }

  Future<void> _prDescription() async {
    final repo = TextEditingController();
    final base = TextEditingController(text: 'main');
    final head = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Generate PR description'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: repo, decoration: fieldDecoration('Repository', hint: 'owner/name')),
            const SizedBox(height: 12),
            TextField(controller: base, decoration: fieldDecoration('Base branch')),
            const SizedBox(height: 12),
            TextField(controller: head, decoration: fieldDecoration('Head branch (your changes)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Generate')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final text = await ref
          .read(githubRepositoryProvider)
          .prDescription(repo: repo.text.trim(), base: base.text.trim(), head: head.text.trim());
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Pull request description'),
          content: SizedBox(width: 560, child: SingleChildScrollView(child: RichContent(content: text))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (mounted) showToast(context, toApiException(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(githubStatusProvider);
    return PageFrame(
      title: 'GitHub',
      subtitle: 'Connect through the backend. Your token stays encrypted on the server.',
      child: status.when(
        loading: () => const Panel(child: SkeletonBox(height: 60)),
        error: (e, _) => ErrorPanel(error: e, onRetry: () => ref.invalidate(githubStatusProvider)),
        data: (s) {
          if (!s.connected) {
            return Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.hub_outlined, color: AppColors.accent),
                  SizedBox(width: 10),
                  Text('Not connected', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ]),
                const SizedBox(height: 8),
                Text('Connect your GitHub account to browse repositories, import code, and generate PR descriptions.',
                    style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  if (s.oauthAvailable)
                    FilledButton.icon(
                        onPressed: _connectOAuth, icon: const Icon(Icons.open_in_new), label: const Text('Connect with GitHub')),
                  OutlinedButton.icon(
                      onPressed: _connectWithToken, icon: const Icon(Icons.key), label: const Text('Use a personal access token')),
                ]),
              ]),
            );
          }
          final repos = ref.watch(githubReposProvider);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Panel(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Connected as ${s.login}')),
                TextButton.icon(
                    onPressed: _prDescription, icon: const Icon(Icons.description_outlined, size: 16), label: const Text('PR description')),
                TextButton(onPressed: _disconnect, child: const Text('Disconnect')),
              ]),
            ),
            const SizedBox(height: 16),
            SearchField(hint: 'Search repositories', onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 16),
            repos.when(
              loading: () => const Panel(child: SkeletonBox(height: 200)),
              error: (e, _) => ErrorPanel(error: e, onRetry: () => ref.invalidate(githubReposProvider)),
              data: (list) {
                final shown = list.where((r) => r.fullName.toLowerCase().contains(_query.toLowerCase())).toList();
                if (shown.isEmpty) {
                  return const Panel(child: EmptyState(icon: Icons.search_off, title: 'No repositories', message: 'Nothing matches your search.'));
                }
                return Column(children: [
                  for (final r in shown) Padding(padding: const EdgeInsets.only(bottom: 10), child: _RepoCard(
                    repo: r,
                    onImport: () => _import(r),
                    onAsk: () => _askAboutRepo(r),
                    onReadme: () => _generateReadme(r),
                  )),
                ]);
              },
            ),
          ]);
        },
      ),
    );
  }
}

class _RepoCard extends StatelessWidget {
  const _RepoCard({required this.repo, required this.onImport, required this.onAsk, required this.onReadme});
  final GithubRepo repo;
  final VoidCallback onImport;
  final VoidCallback onAsk;
  final VoidCallback onReadme;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(repo.isPrivate ? Icons.lock_outline : Icons.public, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(repo.fullName, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          if (repo.stars > 0) ...[
            Icon(Icons.star, size: 14, color: AppColors.accent),
            const SizedBox(width: 3),
            Text('${repo.stars}', style: t.bodySmall),
          ],
        ]),
        if (repo.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(repo.description, style: t.bodySmall?.copyWith(color: AppColors.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 10),
        Row(children: [
          if (repo.language.isNotEmpty) StatusChip(repo.language, color: AppColors.teal),
          const SizedBox(width: 8),
          Text('Updated ${relativeTime(repo.updatedAt)}', style: t.bodySmall?.copyWith(color: AppColors.muted)),
          const Spacer(),
          IconButton(tooltip: 'Ask AI', icon: const Icon(Icons.forum_outlined, size: 18), onPressed: onAsk),
          IconButton(tooltip: 'Generate README', icon: const Icon(Icons.description_outlined, size: 18), onPressed: onReadme),
          FilledButton.tonalIcon(onPressed: onImport, icon: const Icon(Icons.download, size: 16), label: const Text('Import')),
        ]),
      ]),
    );
  }
}
