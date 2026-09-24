import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../../projects/presentation/widgets/project_pickers.dart';
import '../data/agent_repository.dart';
import 'agent_controller.dart';

const _stageIcon = {
  'analysis': Icons.search, 'file_selection': Icons.folder_open, 'modification': Icons.edit_outlined,
  'testing': Icons.fact_check_outlined, 'fixing': Icons.build_outlined, 'report': Icons.summarize_outlined,
};

/// UI for a future autonomous agent (spec section 16). Today it plans a change
/// with AI and shows the steps as a timeline; it does not execute anything.
/// Real execution needs an isolated sandbox on the backend and is not built yet.
class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key, this.projectId});
  final String? projectId;

  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  String? _projectId;
  final _request = TextEditingController();

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
  }

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_projectId == null || _request.text.trim().isEmpty) {
      showToast(context, 'Select a project and describe what you want done.');
      return;
    }
    await ref.read(agentControllerProvider.notifier).plan(projectId: _projectId!, request: _request.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(agentControllerProvider);
    final t = Theme.of(context).textTheme;

    return PageFrame(
      title: 'AI Agent (preview)',
      subtitle: 'Plans a change against your project. It does not modify files or run code yet — '
          'that needs an isolated sandbox on the backend, planned for a later phase.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProjectDropdown(value: _projectId, onChanged: (v) => setState(() => _projectId = v)),
            const SizedBox(height: 12),
            CodeField(
                controller: _request,
                label: 'What do you want done?',
                hint: 'e.g. Add input validation to the login form and handle network errors',
                minLines: 3,
                maxLines: 6),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: plan.isLoading ? null : _run,
              icon: plan.isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.route_outlined),
              label: Text(plan.isLoading ? 'Planning…' : 'Plan'),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        plan.when(
          loading: () => const Panel(
              child: Column(children: [SkeletonBox(height: 16), SizedBox(height: 14), SkeletonBox(height: 180)])),
          error: (e, _) => ErrorPanel(error: e, onRetry: _run),
          data: (p) {
            if (p == null) {
              return const Panel(
                  child: EmptyState(
                      icon: Icons.route_outlined,
                      title: 'No plan yet',
                      message: 'Describe a change above and press Plan to see the steps the agent would take.'));
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Panel(child: Text(p.summary, style: t.bodyLarge)),
              const SizedBox(height: 18),
              Text('Activity timeline', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Panel(
                child: Column(children: [
                  for (var i = 0; i < p.steps.length; i++) _StepRow(step: p.steps[i], last: i == p.steps.length - 1),
                ]),
              ),
              if (p.risks.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Risks & assumptions', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final r in p.risks)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.accent)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(r)),
                        ]),
                      ),
                  ]),
                ),
              ],
            ]);
          },
        ),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.last});
  final AgentStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: AppColors.surfaceHigh, shape: BoxShape.circle),
            child: Icon(_stageIcon[step.stage] ?? Icons.circle, size: 15, color: AppColors.accent),
          ),
          if (!last) Expanded(child: Container(width: 2, color: AppColors.border)),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(step.detail, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
              if (step.files.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final f in step.files) StatusChip(f, color: AppColors.teal),
                ]),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
