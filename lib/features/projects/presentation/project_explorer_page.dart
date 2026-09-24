import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/components/code_block.dart';
import '../../../shared/widgets/search_field.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../../chat/presentation/chat_controller.dart';
import '../domain/project_models.dart';
import 'projects_controller.dart';

class _Node {
  _Node(this.name, this.path);
  final String name;
  final String path;
  final Map<String, _Node> dirs = {};
  final List<ProjectFile> files = [];
}

_Node _buildTree(List<ProjectFile> files) {
  final root = _Node('', '');
  for (final f in files) {
    final parts = f.path.split('/');
    var node = root;
    for (var i = 0; i < parts.length - 1; i++) {
      node = node.dirs.putIfAbsent(parts[i], () => _Node(parts[i], parts.sublist(0, i + 1).join('/')));
    }
    node.files.add(f);
  }
  return root;
}

class ProjectExplorerPage extends ConsumerStatefulWidget {
  const ProjectExplorerPage({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectExplorerPage> createState() => _ProjectExplorerPageState();
}

class _ProjectExplorerPageState extends ConsumerState<ProjectExplorerPage> {
  final Set<String> _expanded = {};
  String _query = '';
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final id = widget.projectId;
    final projects = ref.watch(projectsProvider);
    final files = ref.watch(projectFilesProvider(id));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final project = projects.valueOrNull?.where((p) => p.id == id).firstOrNull;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(children: [
        IconButton(
          tooltip: 'Back to projects',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (!wide && _selected != null) {
              setState(() => _selected = null);
            } else {
              context.go('/projects');
            }
          },
        ),
        Expanded(
          child: Text(project?.name ?? 'Project',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        if (wide) ...[
          TextButton.icon(
              onPressed: () => context.go('/analyzer?project=$id'),
              icon: const Icon(Icons.manage_search, size: 18),
              label: const Text('Analyze')),
          TextButton.icon(
              onPressed: () => context.go('/docs?project=$id'),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Docs')),
        ],
        FilledButton.tonalIcon(
          onPressed: () {
            ref.read(chatControllerProvider.notifier)
              ..newConversation()
              ..setProject(id);
            context.go('/chat');
          },
          icon: const Icon(Icons.forum_outlined, size: 18),
          label: const Text('Ask AI'),
        ),
      ]),
    );

    Widget tree = files.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          SkeletonBox(height: 16), SizedBox(height: 12), SkeletonBox(height: 16),
          SizedBox(height: 12), SkeletonBox(height: 16),
        ]),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: ErrorPanel(error: e, onRetry: () => ref.invalidate(projectFilesProvider(id))),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
              icon: Icons.insert_drive_file_outlined,
              title: 'No files',
              message: 'This project is empty. Upload a ZIP or import a repository to fill it.');
        }
        final rows = <Widget>[];
        if (_query.isNotEmpty) {
          final q = _query.toLowerCase();
          for (final f in list.where((f) => f.path.toLowerCase().contains(q)).take(300)) {
            rows.add(_FileRow(file: f, depth: 0, showPath: true, selected: _selected == f.path,
                onTap: () => setState(() => _selected = f.path)));
          }
          if (rows.isEmpty) {
            rows.add(Padding(
                padding: const EdgeInsets.all(16), child: Text('No files match.', style: TextStyle(color: AppColors.muted))));
          }
        } else {
          void emit(_Node n, int depth) {
            for (final d in (n.dirs.values.toList()..sort((a, b) => a.name.compareTo(b.name)))) {
              final open = _expanded.contains(d.path);
              rows.add(_DirRow(
                  name: d.name, depth: depth, open: open,
                  onTap: () => setState(() => open ? _expanded.remove(d.path) : _expanded.add(d.path))));
              if (open) emit(d, depth + 1);
            }
            for (final f in n.files) {
              rows.add(_FileRow(file: f, depth: depth, selected: _selected == f.path,
                  onTap: () => setState(() => _selected = f.path)));
            }
          }
          emit(_buildTree(list), 0);
        }
        return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: rows);
      },
    );

    final treePanel = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: SearchField(hint: 'Search files', onChanged: (v) => setState(() => _query = v)),
      ),
      Expanded(child: tree),
    ]);

    final preview = _selected == null
        ? const EmptyState(
            icon: Icons.code, title: 'Select a file', message: 'Pick a file from the tree to view its code.')
        : _FilePreview(projectId: id, path: _selected!, key: ValueKey(_selected));

    return Column(children: [
      header,
      const Divider(height: 1),
      Expanded(
        child: wide
            ? Row(children: [
                SizedBox(width: 340, child: Padding(padding: const EdgeInsets.only(top: 10), child: treePanel)),
                VerticalDivider(width: 1, color: AppColors.border),
                Expanded(child: preview),
              ])
            : (_selected == null ? Padding(padding: const EdgeInsets.only(top: 10), child: treePanel) : preview),
      ),
    ]);
  }
}

class _DirRow extends StatelessWidget {
  const _DirRow({required this.name, required this.depth, required this.open, required this.onTap});
  final String name;
  final int depth;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12 + depth * 16.0, 7, 12, 7),
          child: Row(children: [
            Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: AppColors.muted),
            const SizedBox(width: 4),
            Icon(open ? Icons.folder_open : Icons.folder, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.depth, required this.selected, required this.onTap, this.showPath = false});
  final ProjectFile file;
  final int depth;
  final bool selected;
  final bool showPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.surfaceHigh : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12 + depth * 16.0 + (showPath ? 0 : 22), 7, 12, 7),
            child: Row(children: [
              Icon(Icons.insert_drive_file_outlined, size: 17, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(showPath ? file.path : file.name, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      );
}

class _FilePreview extends ConsumerWidget {
  const _FilePreview({super.key, required this.projectId, required this.path});
  final String projectId;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(fileContentProvider((id: projectId, path: path)));
    final lang = ref.watch(projectFilesProvider(projectId)).valueOrNull
            ?.where((f) => f.path == path).firstOrNull?.language ?? '';
    return content.when(
      loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: 240, height: 16), SizedBox(height: 14),
            SkeletonBox(height: 14), SizedBox(height: 10), SkeletonBox(height: 14),
          ])),
      error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorPanel(error: e, onRetry: () => ref.invalidate(fileContentProvider((id: projectId, path: path))))),
      data: (code) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(children: [
            Expanded(child: Text(path, style: AppTheme.mono(size: 13), overflow: TextOverflow.ellipsis)),
            IconButton(
              tooltip: 'Copy file',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) showToast(context, 'File copied');
              },
            ),
            IconButton(
              tooltip: 'Analyze this file',
              icon: const Icon(Icons.manage_search, size: 20),
              onPressed: () => context.go(
                  '/analyzer?project=$projectId&path=${Uri.encodeQueryComponent(path)}'),
            ),
            IconButton(
              tooltip: 'Generate tests',
              icon: const Icon(Icons.fact_check_outlined, size: 20),
              onPressed: () => context.go(
                  '/tests?project=$projectId&path=${Uri.encodeQueryComponent(path)}'),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: CodeBlock(
                code: code.isEmpty ? '(empty file)' : code,
                language: lang,
                fileName: path.split('/').last.split('.').first,
                maxLines: 2000),
          ),
        ),
      ]),
    );
  }
}
