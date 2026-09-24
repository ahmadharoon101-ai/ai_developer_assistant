import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/components/rich_content.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../../projects/presentation/widgets/project_pickers.dart';
import '../data/analyzer_repository.dart';
import 'analyzer_controller.dart';

const _focusLabels = {
  'explain': 'Explain code',
  'bugs': 'Find bugs',
  'smells': 'Code smells',
  'complexity': 'Complexity',
  'improve': 'Improvements',
  'security': 'Security',
  'performance': 'Performance',
};

const _languages = ['Python', 'Dart', 'JavaScript', 'TypeScript', 'Java', 'C#', 'C++', 'Go', 'Rust', 'SQL', 'Other'];

Color severityColor(String s) => switch (s) {
      'critical' || 'high' => AppColors.danger,
      'medium' => AppColors.accent,
      'low' => AppColors.teal,
      _ => AppColors.muted,
    };

class AnalyzerPage extends ConsumerStatefulWidget {
  const AnalyzerPage({super.key, this.projectId, this.path, this.autorun = false});
  final String? projectId;
  final String? path;
  final bool autorun;

  @override
  ConsumerState<AnalyzerPage> createState() => _AnalyzerPageState();
}

class _AnalyzerPageState extends ConsumerState<AnalyzerPage> {
  final _code = TextEditingController();
  bool _pasteMode = false;
  String? _projectId;
  String? _path;
  String _language = 'Python';
  Set<String> _focus = {'bugs', 'smells', 'security'};
  String _severity = 'all';

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _path = widget.path;
    if (widget.autorun && _projectId != null) {
      _focus = {'bugs', 'smells', 'security', 'improve'};
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_pasteMode ? _code.text.trim().isEmpty : _projectId == null) {
      showToast(context, _pasteMode ? 'Paste some code first.' : 'Select a project first.');
      return;
    }
    if (_focus.isEmpty) {
      showToast(context, 'Pick at least one analysis type.');
      return;
    }
    setState(() => _severity = 'all');
    await ref.read(analyzerControllerProvider.notifier).run(
          projectId: _pasteMode ? null : _projectId,
          path: _pasteMode ? null : _path,
          code: _pasteMode ? _code.text : null,
          language: _language,
          focus: _focus.toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(analyzerControllerProvider);
    final t = Theme.of(context).textTheme;

    return PageFrame(
      title: 'Code Analyzer',
      subtitle: 'Explain code, find bugs, smells, security and performance problems.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.folder_outlined), label: Text('Project')),
                ButtonSegment(value: true, icon: Icon(Icons.data_object), label: Text('Paste code')),
              ],
              selected: {_pasteMode},
              onSelectionChanged: (s) => setState(() => _pasteMode = s.first),
            ),
            const SizedBox(height: 16),
            if (!_pasteMode) ...[
              ProjectDropdown(
                  value: _projectId,
                  onChanged: (v) => setState(() {
                        _projectId = v;
                        _path = null;
                      })),
              const SizedBox(height: 12),
              FileDropdown(
                  projectId: _projectId,
                  value: _path,
                  allowWhole: true,
                  onChanged: (v) => setState(() => _path = v)),
            ] else ...[
              AppDropdown<String>(
                label: 'Language',
                value: _language,
                items: [for (final l in _languages) DropdownMenuItem(value: l, child: Text(l))],
                onChanged: (v) => setState(() => _language = v ?? _language),
              ),
              const SizedBox(height: 12),
              CodeField(controller: _code, label: 'Code', hint: 'Paste the code to analyze…'),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in _focusLabels.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _focus.contains(e.key),
                  showCheckmark: false,
                  selectedColor: AppColors.accent.withOpacity(0.22),
                  side: BorderSide(color: AppColors.border),
                  onSelected: (on) => setState(() => on ? _focus.add(e.key) : _focus.remove(e.key)),
                ),
            ]),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: result.isLoading ? null : _run,
              icon: result.isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(result.isLoading ? 'Analyzing…' : 'Analyze'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        result.when(
          loading: () => const Panel(
            child: Column(children: [
              SkeletonBox(height: 16), SizedBox(height: 14), SkeletonBox(height: 16),
              SizedBox(height: 14), SkeletonBox(height: 16),
            ]),
          ),
          error: (e, _) => ErrorPanel(error: e, onRetry: _run),
          data: (r) {
            if (r == null) {
              return const Panel(
                child: EmptyState(
                  icon: Icons.manage_search,
                  title: 'No analysis yet',
                  message: 'Choose what to analyze and press Analyze. Results appear here as issue cards.',
                ),
              );
            }
            final order = ['critical', 'high', 'medium', 'low', 'info'];
            final issues = r.issues
                .where((i) => _severity == 'all' || i.severity == _severity)
                .toList()
              ..sort((a, b) => order.indexOf(a.severity).compareTo(order.indexOf(b.severity)));
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Summary', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (r.complexity.isNotEmpty) StatusChip('Complexity: ${r.complexity}', color: AppColors.teal),
                    const SizedBox(width: 8),
                    StatusChip('${r.filesAnalyzed} file${r.filesAnalyzed == 1 ? '' : 's'}', color: AppColors.muted),
                  ]),
                  const SizedBox(height: 10),
                  RichContent(content: r.summary),
                ]),
              ),
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${r.issues.length} issue${r.issues.length == 1 ? '' : 's'}',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                for (final s in ['all', ...order])
                  ChoiceChip(
                    label: Text(s[0].toUpperCase() + s.substring(1)),
                    selected: _severity == s,
                    onSelected: (_) => setState(() => _severity = s),
                  ),
              ]),
              const SizedBox(height: 12),
              if (issues.isEmpty)
                const Panel(
                    child: EmptyState(
                        icon: Icons.verified_outlined,
                        title: 'Nothing to show',
                        message: 'No issues at this severity.'))
              else
                for (final i in issues) Padding(padding: const EdgeInsets.only(bottom: 12), child: IssueCard(issue: i)),
            ]);
          },
        ),
      ]),
    );
  }
}

class IssueCard extends StatelessWidget {
  const IssueCard({super.key, required this.issue});
  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = severityColor(issue.severity);
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StatusChip(issue.severity.toUpperCase(), color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(issue.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        if (issue.location.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 15, color: AppColors.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(issue.location, style: AppTheme.mono(size: 12.5, color: AppColors.muted))),
          ]),
        ],
        const SizedBox(height: 10),
        Text('Explanation', style: t.labelMedium?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 4),
        RichContent(content: issue.explanation),
        if (issue.suggestedFix.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Text('Suggested fix', style: t.labelMedium?.copyWith(color: AppColors.muted)),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: issue.suggestedFix));
                if (context.mounted) showToast(context, 'Fix copied');
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy'),
            ),
          ]),
          RichContent(content: issue.suggestedFix),
        ],
      ]),
    );
  }
}
