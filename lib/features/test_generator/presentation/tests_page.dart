import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_export.dart';
import '../../../shared/components/rich_content.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../../projects/presentation/widgets/project_pickers.dart';
import 'tests_controller.dart';

const _kindOptions = {
  'unit': 'Unit', 'integration': 'Integration', 'api': 'API', 'edge': 'Edge cases', 'negative': 'Negative',
};

class TestsPage extends ConsumerStatefulWidget {
  const TestsPage({super.key, this.projectId, this.path});
  final String? projectId;
  final String? path;

  @override
  ConsumerState<TestsPage> createState() => _TestsPageState();
}

class _TestsPageState extends ConsumerState<TestsPage> {
  String? _projectId;
  String? _path;
  final _symbol = TextEditingController();
  final _framework = TextEditingController();
  Set<String> _kinds = {'unit', 'edge', 'negative'};

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _path = widget.path;
  }

  @override
  void dispose() {
    _symbol.dispose();
    _framework.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_projectId == null || _path == null) {
      showToast(context, 'Select a project and a file first.');
      return;
    }
    await ref.read(testsControllerProvider.notifier).run(
          projectId: _projectId!,
          path: _path!,
          symbol: _symbol.text.trim(),
          kinds: _kinds.toList(),
          framework: _framework.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(testsControllerProvider);
    final t = Theme.of(context).textTheme;

    return PageFrame(
      title: 'Test Generator',
      subtitle: 'Pick a project, a file and (optionally) a function to generate tests for.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProjectDropdown(
                value: _projectId,
                onChanged: (v) => setState(() {
                      _projectId = v;
                      _path = null;
                    })),
            const SizedBox(height: 12),
            FileDropdown(projectId: _projectId, value: _path, onChanged: (v) => setState(() => _path = v)),
            const SizedBox(height: 12),
            TextField(
                controller: _symbol,
                decoration:
                    fieldDecoration('Function or class (optional)', hint: 'Leave empty for all public symbols')),
            const SizedBox(height: 12),
            TextField(
                controller: _framework,
                decoration: fieldDecoration('Test framework (optional)', hint: 'e.g. pytest, flutter_test, jest')),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in _kindOptions.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _kinds.contains(e.key),
                  showCheckmark: false,
                  selectedColor: AppColors.accent.withOpacity(0.22),
                  side: BorderSide(color: AppColors.border),
                  onSelected: (on) => setState(() => on ? _kinds.add(e.key) : _kinds.remove(e.key)),
                ),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: result.isLoading ? null : _run,
              icon: result.isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.fact_check_outlined),
              label: Text(result.isLoading ? 'Writing tests…' : 'Generate tests'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        result.when(
          loading: () => const Panel(
              child: Column(children: [SkeletonBox(height: 16), SizedBox(height: 14), SkeletonBox(height: 220)])),
          error: (e, _) => ErrorPanel(error: e, onRetry: _run),
          data: (text) {
            if (text == null) {
              return const Panel(
                  child: EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'No tests yet',
                      message: 'Choose a project and file above, then press Generate tests.'));
            }
            return Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Generated tests', style: t.titleMedium)),
                  TextButton.icon(
                    onPressed: () {
                      final snippet = firstCodeBlock(text);
                      if (snippet == null) return;
                      exportText('tests_${_path?.split('/').last.split('.').first ?? 'file'}',
                          extensionFor(snippet.language.isEmpty ? _language(_path) : snippet.language), snippet.code);
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download'),
                  ),
                ]),
                const SizedBox(height: 8),
                RichContent(content: text, streaming: result.isLoading),
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
