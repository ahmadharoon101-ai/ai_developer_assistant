import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/search_field.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../domain/project_models.dart';
import 'projects_controller.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  String _query = '';
  String _language = '';

  Future<void> _run(String working, Future<Project> Function() job) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 18),
          Expanded(child: Text(working)),
        ]),
      ),
    );
    try {
      final p = await job();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, '"${p.name}" added (${p.fileCount} files)');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, toApiException(e).message);
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final framework = TextEditingController();
    String language = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('New project'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  autofocus: true,
                  decoration: fieldDecoration('Project name')),
              const SizedBox(height: 12),
              AppDropdown<String>(
                label: 'Language (optional)',
                value: language,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Not set')),
                  for (final l in const ['Python', 'Dart', 'JavaScript', 'TypeScript', 'Java', 'C#', 'C++', 'Go', 'Rust'])
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: (v) => setLocal(() => language = v ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: framework,
                  decoration: fieldDecoration('Framework (optional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await _run(
        'Creating project…',
        () => ref
            .read(projectsProvider.notifier)
            .create(name.text.trim(), language: language, framework: framework.text.trim()));
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) showToast(context, 'Could not read that file.');
      return;
    }
    if (bytes.length > 30 * 1024 * 1024) {
      if (mounted) showToast(context, 'ZIP is too large (max 30 MB).');
      return;
    }
    await _run('Uploading and reading ${file.name}…',
        () => ref.read(projectsProvider.notifier).upload(bytes, file.name));
  }

  Future<void> _import() async {
    final repo = TextEditingController();
    final branch = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Import GitHub repository'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: repo,
                autofocus: true,
                decoration: fieldDecoration('Repository', hint: 'owner/name')),
            const SizedBox(height: 12),
            TextField(
                controller: branch,
                decoration: fieldDecoration('Branch or tag (optional)')),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Requires GitHub to be connected. You can browse your repositories on the GitHub page.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true || repo.text.trim().isEmpty) return;
    await _run(
        'Downloading ${repo.text.trim()}…',
        () => ref
            .read(projectsProvider.notifier)
            .importGithub(repo.text.trim(), ref: branch.text.trim()));
  }

  Future<void> _delete(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete project?'),
        content: Text('"${p.name}" and its stored files will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(projectsProvider.notifier).delete(p.id);
      if (mounted) showToast(context, 'Project deleted');
    } catch (e) {
      if (mounted) showToast(context, toApiException(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    return PageFrame(
      title: 'Projects',
      subtitle: 'Bring your code in. Uploaded files are stored as text and never executed.',
      actions: [
        FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New')),
        OutlinedButton.icon(onPressed: _upload, icon: const Icon(Icons.upload_file), label: const Text('Upload ZIP')),
        OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.hub_outlined), label: const Text('Import from GitHub')),
      ],
      child: projects.when(
        loading: () => ResponsiveGrid(minItemWidth: 300, children: [
          for (var i = 0; i < 3; i++)
            const Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SkeletonBox(width: 140, height: 18),
                SizedBox(height: 12),
                SkeletonBox(width: 200, height: 12),
                SizedBox(height: 18),
                SkeletonBox(height: 12),
              ]),
            ),
        ]),
        error: (e, _) => ErrorPanel(error: e, onRetry: () => ref.invalidate(projectsProvider)),
        data: (all) {
          if (all.isEmpty) {
            return Panel(
              child: EmptyState(
                icon: Icons.folder_open,
                title: 'No projects yet',
                message: 'Upload a ZIP, import a GitHub repository, or create an empty project.',
                action: FilledButton.icon(
                    onPressed: _upload, icon: const Icon(Icons.upload_file), label: const Text('Upload ZIP')),
              ),
            );
          }
          final langs = {for (final p in all) if (p.language.isNotEmpty) p.language}.toList()..sort();
          final shown = all.where((p) {
            final q = _query.toLowerCase();
            final matches = q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                p.framework.toLowerCase().contains(q);
            return matches && (_language.isEmpty || p.language == _language);
          }).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: SearchField(hint: 'Search projects', onChanged: (v) => setState(() => _query = v))),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: AppDropdown<String>(
                  label: 'Language',
                  value: langs.contains(_language) ? _language : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All')),
                    for (final l in langs) DropdownMenuItem(value: l, child: Text(l)),
                  ],
                  onChanged: (v) => setState(() => _language = v ?? ''),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            if (shown.isEmpty)
              const Panel(child: EmptyState(icon: Icons.search_off, title: 'No matches', message: 'Try a different search or filter.'))
            else
              ResponsiveGrid(minItemWidth: 300, children: [
                for (final p in shown) _ProjectCard(project: p, onDelete: () => _delete(p)),
              ]),
          ]);
        },
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onDelete});
  final Project project;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final t = Theme.of(context).textTheme;
    final meta = [
      if (p.language.isNotEmpty) p.language,
      if (p.framework.isNotEmpty) p.framework,
    ].join(' · ');
    return Panel(
      onTap: () => context.go('/projects/${p.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(p.source == 'github' ? Icons.hub_outlined : Icons.folder_outlined, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          PopupMenuButton<String>(
            tooltip: 'More',
            color: AppColors.surfaceHigh,
            onSelected: (v) {
              switch (v) {
                case 'open':
                  context.go('/projects/${p.id}');
                case 'analyze':
                  context.go('/analyzer?project=${p.id}');
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'open', child: Text('Open')),
              PopupMenuItem(value: 'analyze', child: Text('Analyze')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        const SizedBox(height: 4),
        Text(meta.isEmpty ? 'Language not detected' : meta,
            style: t.bodySmall?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 14),
        Row(children: [
          Text('${p.fileCount} files', style: t.bodySmall),
          const Spacer(),
          StatusChip(p.status),
        ]),
        const SizedBox(height: 8),
        Text('Last analyzed: ${p.lastAnalyzed == null ? 'never' : relativeTime(p.lastAnalyzed)}',
            style: t.bodySmall?.copyWith(color: AppColors.muted)),
      ]),
    );
  }
}
