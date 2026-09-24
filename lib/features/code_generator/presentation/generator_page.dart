import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_export.dart';
import '../../../shared/components/rich_content.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/data/saved_repository.dart';
import '../../../shared/widgets/saved_items_button.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import 'generator_controller.dart';

const _languages = ['Python', 'Dart', 'JavaScript', 'TypeScript', 'Java', 'C#', 'C++', 'Go', 'Rust'];
const _frameworks = ['None', 'Flutter', 'FastAPI', 'Django', 'React', 'Next.js', 'Node.js'];
const _kinds = ['Function', 'Class', 'API endpoint', 'Database model', 'UI component', 'Authentication', 'Tests'];

class GeneratorPage extends ConsumerStatefulWidget {
  const GeneratorPage({super.key});

  @override
  ConsumerState<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends ConsumerState<GeneratorPage> {
  final _prompt = TextEditingController();
  String _language = 'Python';
  String _framework = 'None';
  String _kind = 'Function';

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_prompt.text.trim().isEmpty) {
      showToast(context, 'Describe what you want to build.');
      return;
    }
    await ref.read(generatorControllerProvider.notifier).run(
          mode: 'generate',
          language: _language,
          framework: _framework == 'None' ? '' : _framework,
          kind: _kind,
          prompt: _prompt.text,
        );
  }

  Future<void> _rewrite(String mode) async {
    final current = ref.read(generatorControllerProvider).valueOrNull;
    if (current == null) return;
    await ref.read(generatorControllerProvider.notifier).run(
          mode: mode, language: _language, framework: _framework == 'None' ? '' : _framework, code: current,
        );
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(generatorControllerProvider);

    return PageFrame(
      title: 'Code Generator',
      subtitle: 'Describe what you want to build and generate it in your language and framework.',
      actions: [
        SavedItemsButton(
          kind: 'generator',
          onLoad: (p) {
            setState(() {
              _prompt.text = p['prompt'] as String? ?? '';
              _language = (p['language'] as String?) ?? _language;
              _framework = (p['framework'] as String?) ?? _framework;
              _kind = (p['kind'] as String?) ?? _kind;
            });
            final content = p['content'] as String?;
            if (content != null) ref.read(generatorControllerProvider.notifier).setResult(content);
          },
        ),
      ],
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 4,
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppDropdown<String>(
                label: 'Language',
                value: _language,
                items: [for (final l in _languages) DropdownMenuItem(value: l, child: Text(l))],
                onChanged: (v) => setState(() => _language = v ?? _language),
              ),
              const SizedBox(height: 12),
              AppDropdown<String>(
                label: 'Framework',
                value: _framework,
                items: [for (final f in _frameworks) DropdownMenuItem(value: f, child: Text(f))],
                onChanged: (v) => setState(() => _framework = v ?? _framework),
              ),
              const SizedBox(height: 12),
              AppDropdown<String>(
                label: 'Kind',
                value: _kind,
                items: [for (final k in _kinds) DropdownMenuItem(value: k, child: Text(k))],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const SizedBox(height: 12),
              CodeField(
                  controller: _prompt,
                  label: 'Describe what you want to build…',
                  minLines: 6,
                  maxLines: 12),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: result.isLoading ? null : _run,
                icon: result.isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(result.isLoading ? 'Generating…' : 'Generate'),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 6,
          child: result.when(
            loading: () => const Panel(
                child: Column(children: [
              SkeletonBox(height: 16), SizedBox(height: 14), SkeletonBox(height: 200),
            ])),
            error: (e, _) => ErrorPanel(error: e, onRetry: _run),
            data: (text) {
              if (text == null) {
                return const Panel(
                    child: EmptyState(
                  icon: Icons.code,
                  title: 'Nothing generated yet',
                  message: 'Describe what you want on the left and press Generate.',
                ));
              }
              return Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Generated code', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton.icon(
                      onPressed: result.isLoading ? null : () => _rewrite('explain'),
                      icon: const Icon(Icons.lightbulb_outline, size: 16),
                      label: const Text('Explain'),
                    ),
                    TextButton.icon(
                      onPressed: result.isLoading ? null : () => _rewrite('improve'),
                      icon: const Icon(Icons.trending_up, size: 16),
                      label: const Text('Improve'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await ref.read(savedRepositoryProvider).save('generator',
                              _prompt.text.trim().isEmpty ? 'Generated code' : _prompt.text.trim().split('\n').first,
                              {'prompt': _prompt.text, 'language': _language, 'framework': _framework, 'kind': _kind, 'content': text});
                          if (context.mounted) showToast(context, 'Saved');
                        } catch (e) {
                          if (context.mounted) showToast(context, toApiException(e).message);
                        }
                      },
                      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                      label: const Text('Save'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  RichContent(content: text, streaming: result.isLoading),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}
