import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/brand_mark.dart';

/// Two-pane on wide screens (brand + agent timeline), single column on mobile.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final t = Theme.of(context).textTheme;

    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!wide) ...[
                const BrandMark(size: 44),
                const SizedBox(height: 20),
              ],
              Text(title,
                  style: t.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(subtitle,
                  style: t.bodyMedium?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                VerticalDivider(width: 1, color: AppColors.border),
                Expanded(flex: 4, child: form),
              ])
            : form,
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _steps = [
    'Analyzed project',
    'Identified relevant files',
    'Modified authentication service',
    'Generated tests',
    'Fixed failing test',
    'All tests passed',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      color: AppColors.sidebar,
      padding: const EdgeInsets.all(56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const BrandMark(size: 40),
            const SizedBox(width: 14),
            Text('AI Developer Assistant',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          const Spacer(),
          for (final w in const ['Build.', 'Debug.', 'Understand.', 'Ship.'])
            Text(w,
                style: t.displayMedium?.copyWith(
                    fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -1)),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.codeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in _steps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Text('✓ ',
                          style: AppTheme.mono(color: AppColors.success)),
                      Text(s,
                          style: AppTheme.mono(color: AppColors.muted)),
                    ]),
                  ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
