import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_export.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../../projects/presentation/widgets/project_pickers.dart';
import 'docs_controller.dart';

const _docTypes = {
  'readme': ('README', Icons.description_outlined),
  'api': ('API documentation', Icons.api),
  'install': ('Installation guide', Icons.install_desktop_outlined),
  'architecture': ('Architecture', Icons.account_tree_outlined),
  'developer': ('Developer guide', Icons.menu_book_outlined),
  'comments': ('Code comments', Icons.comment_outlined),
};

class DocsPage extends ConsumerStatefulWidget {
  const DocsPage({super.key, this.projectId});
  final String? projectId;

  @override
  ConsumerState<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends ConsumerState<DocsPage> {
  String? _projectId;
  String _docType = 'readme';
  String? _path;
  late final TextEditingController _editor = TextEditingController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_projectId == null) {
      showToast(context, 'Select a project first.');
      return;
    }
    if (_docType == 'comments' && _path == null) {
      showToast(context, 'Pick a file to add comments to.');
      return;
    }
    setState(() => _editing = false);
    await ref
        .read(docsControllerProvider.notifier)
        .run(projectId: _projectId!, docType: _docType, path: _docType == 'comments' ? _path : null);
    final text = ref.read(docsControllerProvider).valueOrNull;
    if (text != null) _editor.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(docsControllerProvider);
    final t = Theme.of(context).textTheme;

    return PageFrame(
      title: 'Documentation',
      subtitle: 'Generate, preview and edit documentation for a project.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProjectDropdown(value: _projectId, onChanged: (v) => setState(() => _projectId = v)),
            const SizedBox(height: 12),
            AppDropdown<String>(
              label: 'Document type',
              value: _docType,
              items: [
                for (final e in _docTypes.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value.$1))
              ],
              onChanged: (v) => setState(() => _docType = v ?? _docType),
            ),
            if (_docType == 'comments') ...[
              const SizedBox(height: 12),
              FileDropdown(projectId: _projectId, value: _path, onChanged: (v) => setState(() => _path = v)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: result.isLoading ? null : _run,
              icon: result.isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(result.isLoading ? 'Writing…' : 'Generate'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        result.when(
          loading: () => const Panel(
              child: Column(children: [SkeletonBox(height: 16), SizedBox(height: 14), SkeletonBox(height: 240)])),
          error: (e, _) => ErrorPanel(error: e, onRetry: _run),
          data: (text) {
            if (text == null) {
              return const Panel(
                  child: EmptyState(
                      icon: Icons.description_outlined,
                      title: 'Nothing generated yet',
                      message: 'Pick a project and document type, then press Generate.'));
            }
            return Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_docTypes[_docType]!.$1, style: t.titleMedium)),
                  IconButton(
                    tooltip: _editing ? 'Preview' : 'Edit',
                    icon: Icon(_editing ? Icons.visibility_outlined : Icons.edit_outlined),
                    onPressed: () => setState(() {
                      if (_editing) ref.read(docsControllerProvider.notifier).setContent(_editor.text);
                      _editing = !_editing;
                    }),
                  ),
                  IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () => exportText(
                        _docType == 'readme' ? 'README' : _docType,
                        _docType == 'comments' ? extensionFor(_language(_path)) : 'md',
                        _editing ? _editor.text : text),
                  ),
                ]),
                const SizedBox(height: 8),
                _editing
                    ? CodeField(controller: _editor, label: 'Edit', minLines: 14, maxLines: 40)
                    : SingleChildScrollView(
                        child: SelectableText(text, style: AppTheme.mono(size: 13.5, color: AppColors.text))),
              ]),
            );
          },
        ),
      ]),
    );
  }

  String _language(String? path) {
    final ext = path?.split('.').last ?? '';
    return const {'py': 'python', 'dart': 'dart', 'js': 'javascript', 'ts': 'typescript'}[ext] ?? '';
  }
}
