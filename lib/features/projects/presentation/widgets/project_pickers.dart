import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_dropdown.dart';
import '../../../../shared/widgets/panel.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/state_widgets.dart';
import '../projects_controller.dart';

/// Dropdown of the user's real projects. `value` null/'' means "none".
class ProjectDropdown extends ConsumerWidget {
  const ProjectDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Project',
    this.allowNone = false,
    this.noneLabel = 'None',
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final bool allowNone;
  final String noneLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return projects.when(
      loading: () => const SkeletonBox(height: 52, radius: 8),
      error: (e, _) =>
          ErrorPanel(error: e, onRetry: () => ref.invalidate(projectsProvider)),
      data: (list) {
        if (list.isEmpty) {
          return Panel(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.folder_off_outlined, color: AppColors.muted),
              const SizedBox(width: 12),
              const Expanded(child: Text('You have no projects yet.')),
              TextButton(
                  onPressed: () => context.go('/projects'),
                  child: const Text('Add a project')),
            ]),
          );
        }
        final ids = list.map((p) => p.id).toSet();
        final current = (value != null && ids.contains(value)) ? value : (allowNone ? '' : null);
        return AppDropdown<String>(
          label: label,
          value: current,
          hint: allowNone ? null : 'Select a project',
          items: [
            if (allowNone) DropdownMenuItem(value: '', child: Text(noneLabel)),
            for (final p in list)
              DropdownMenuItem(
                value: p.id,
                child: Text(
                    p.language.isEmpty ? p.name : '${p.name}  ·  ${p.language}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => onChanged((v == null || v.isEmpty) ? null : v),
        );
      },
    );
  }
}

/// Dropdown of files inside a project. `value` null/'' means the whole project (if allowed).
class FileDropdown extends ConsumerWidget {
  const FileDropdown({
    super.key,
    required this.projectId,
    required this.value,
    required this.onChanged,
    this.label = 'File',
    this.allowWhole = false,
    this.wholeLabel = 'Whole project',
  });

  final String? projectId;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final bool allowWhole;
  final String wholeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (projectId == null) {
      return AppDropdown<String>(
          label: label, value: null, hint: 'Select a project first', items: const [], onChanged: null);
    }
    final files = ref.watch(projectFilesProvider(projectId!));
    return files.when(
      loading: () => const SkeletonBox(height: 52, radius: 8),
      error: (e, _) => ErrorPanel(
          error: e, onRetry: () => ref.invalidate(projectFilesProvider(projectId!))),
      data: (list) {
        final paths = list.map((f) => f.path).toSet();
        final current = (value != null && paths.contains(value)) ? value : (allowWhole ? '' : null);
        return AppDropdown<String>(
          label: label,
          value: current,
          hint: list.isEmpty ? 'This project has no files' : 'Select a file',
          items: [
            if (allowWhole) DropdownMenuItem(value: '', child: Text(wholeLabel)),
            for (final f in list)
              DropdownMenuItem(value: f.path, child: Text(f.path, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onChanged((v == null || v.isEmpty) ? null : v),
        );
      },
    );
  }
}
