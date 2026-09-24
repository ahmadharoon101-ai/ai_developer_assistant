import 'package:flutter/material.dart';

import '../../core/errors/failures.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import 'panel.dart';

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ApiException ? (error as ApiException).message : toApiException(error).message;
    return Panel(
      child: Row(children: [
        Icon(Icons.error_outline, color: AppColors.danger),
        const SizedBox(width: 12),
        Expanded(child: Text(msg)),
        if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: AppColors.muted),
              const SizedBox(height: 14),
              Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: AppColors.muted)),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ??
        switch (label) {
          'Healthy' => AppColors.success,
          'Needs review' => AppColors.accent,
          _ => AppColors.muted,
        };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    );
  }
}

/// Standard page frame: title, optional subtitle/actions, centered max-width body.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.maxWidth = 1080,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
                      ],
                    ],
                  ),
                  if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ),
              const SizedBox(height: 22),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.minLines = 6,
    this.maxLines = 18,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int minLines;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      keyboardType: TextInputType.multiline,
      style: AppTheme.mono(size: 13),
      decoration: fieldDecoration(label, hint: hint).copyWith(alignLabelWithHint: true),
    );
  }
}
