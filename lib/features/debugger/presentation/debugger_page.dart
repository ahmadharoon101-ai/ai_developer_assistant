import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/components/code_block.dart';
import '../../../shared/components/rich_content.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/data/saved_repository.dart';
import '../../../shared/widgets/saved_items_button.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../../chat/presentation/chat_controller.dart';
import '../data/debugger_repository.dart';
import 'debugger_controller.dart';

const _languages = ['Auto-detect', 'Python', 'Dart', 'JavaScript', 'TypeScript', 'Java', 'C#', 'C++', 'Go', 'Rust', 'Shell'];

class DebuggerPage extends ConsumerStatefulWidget {
  const DebuggerPage({super.key});

  @override
  ConsumerState<DebuggerPage> createState() => _DebuggerPageState();
}

class _DebuggerPageState extends ConsumerState<DebuggerPage> {
  final _error = TextEditingController();
  final _stack = TextEditingController();
  final _code = TextEditingController();
  String _language = 'Auto-detect';

  @override
  void dispose() {
    _error.dispose();
    _stack.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_error.text.trim().isEmpty) {
      showToast(context, 'Paste the error message first.');
      return;
    }
    await ref.read(debuggerControllerProvider.notifier).run(
          error: _error.text,
          stackTrace: _stack.text,
          code: _code.text,
          language: _language == 'Auto-detect' ? '' : _language,
        );
  }

  Future<void> _save(DebugResult r) async {
    try {
      await ref.read(savedRepositoryProvider).save('debug',
          _error.text.trim().split('\n').first.substring(0, _error.text.trim().split('\n').first.length.clamp(0, 60)),
          {'error': _error.text, 'stack_trace': _stack.text, 'code': _code.text, 'language': _language});
      if (mounted) showToast(context, 'Debug session saved');
    } catch (e) {
      if (mounted) showToast(context, toApiException(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(debuggerControllerProvider);
    final t = Theme.of(context).textTheme;

    return PageFrame(
      title: 'Debugger',
      subtitle: 'Paste an error, stack trace and code for a structured diagnosis.',
      actions: [
        SavedItemsButton(
          kind: 'debug',
          onLoad: (p) => setState(() {
            _error.text = p['error'] as String? ?? '';
            _stack.text = p['stack_trace'] as String? ?? '';
            _code.text = p['code'] as String? ?? '';
            _language = (p['language'] as String?) ?? 'Auto-detect';
          }),
        ),
      ],
      maxWidth: 900,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CodeField(controller: _error, label: 'Error message', minLines: 2, maxLines: 5,
                hint: "e.g. ModuleNotFoundError: No module named 'fastapi'"),
            const SizedBox(height: 12),
            CodeField(controller: _stack, label: 'Stack trace (optional)', minLines: 3, maxLines: 10),
            const SizedBox(height: 12),
            CodeField(controller: _code, label: 'Relevant code (optional)', minLines: 3, maxLines: 12),
            const SizedBox(height: 12),
            AppDropdown<String>(
              label: 'Language',
              value: _language,
              items: [for (final l in _languages) DropdownMenuItem(value: l, child: Text(l))],
              onChanged: (v) => setState(() => _language = v ?? _language),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: result.isLoading ? null : _run,
              icon: result.isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bug_report_outlined),
              label: Text(result.isLoading ? 'Diagnosing…' : 'Diagnose'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        result.when(
          loading: () => const Panel(
              child: Column(children: [
            SkeletonBox(height: 16), SizedBox(height: 14), SkeletonBox(height: 16), SizedBox(height: 14), SkeletonBox(height: 16),
          ])),
          error: (e, _) => ErrorPanel(error: e, onRetry: _run),
          data: (r) {
            if (r == null) {
              return const Panel(
                  child: EmptyState(
                icon: Icons.bug_report_outlined,
                title: 'No diagnosis yet',
                message: 'Paste an error above and press Diagnose.',
              ));
            }
            Widget section(String title, Color color, Widget child) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                    const SizedBox(height: 8),
                    child,
                  ]),
                );
            return Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                section('Problem', AppColors.danger, RichContent(content: r.problem)),
                section('Cause', AppColors.accent, RichContent(content: r.cause)),
                section('Solution', AppColors.success, RichContent(content: r.solution)),
                section('Explanation', AppColors.teal, RichContent(content: r.explanation)),
                Row(children: [
                  if (r.fixCode.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        await ref
                            .read(chatControllerProvider.notifier)
                            .startWith('Apply this fix to my code and explain what changed:\n\n```${r.fixLanguage}\n${r.fixCode}\n```');
                        if (context.mounted) context.go('/chat');
                      },
                      icon: const Icon(Icons.auto_fix_high, size: 16),
                      label: const Text('Apply fix in chat'),
                    ),
                  TextButton.icon(
                    onPressed: () async {
                      await ref
                          .read(chatControllerProvider.notifier)
                          .startWith('I have this error:\n\n${_error.text}\n\nCan you explain more and suggest alternatives?');
                      if (context.mounted) context.go('/chat');
                    },
                    icon: const Icon(Icons.forum_outlined, size: 16),
                    label: const Text('Ask AI'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _save(r),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: const Text('Save session'),
                  ),
                ]),
              ]),
            );
          },
        ),
      ]),
    );
  }
}
