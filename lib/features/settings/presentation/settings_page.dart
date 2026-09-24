import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_widgets.dart';
import '../../../shared/widgets/toast.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/theme/theme_controller.dart';
import '../../github/data/github_repository.dart';
import '../data/settings_repository.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _name =
      TextEditingController(text: ref.read(authControllerProvider).valueOrNull?.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_name.text.trim().isEmpty) return;
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(_name.text.trim());
      if (mounted) showToast(context, 'Profile updated');
    } catch (e) {
      if (mounted) showToast(context, toApiException(e).message);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Change password'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: current, obscureText: true, decoration: fieldDecoration('Current password')),
            const SizedBox(height: 12),
            TextField(
                controller: next,
                obscureText: true,
                decoration: fieldDecoration('New password', hint: 'At least 8 characters, letter + number')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(authControllerProvider.notifier).changePassword(current.text, next.text);
      if (mounted) showToast(context, 'Password changed');
    } catch (e) {
      if (mounted) showToast(context, toApiException(e).message);
    }
  }

  Future<void> _confirmSignOut({bool everywhere = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(everywhere ? 'Sign out everywhere?' : 'Sign out?'),
        content: Text(everywhere
            ? 'This ends every session on every device, including this one.'
            : 'You will need to sign in again to use the assistant.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    if (everywhere) {
      await ref.read(authControllerProvider.notifier).signOutEverywhere();
    } else {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final settings = ref.watch(appSettingsProvider);
    final github = ref.watch(githubStatusProvider);
    final themeMode = ref.watch(themeModeProvider);
    final t = Theme.of(context).textTheme;

    Widget sectionTitle(String s) =>
        Text(s, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              sectionTitle('Account'),
              const SizedBox(height: 10),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: _name, decoration: fieldDecoration('Full name')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.mail_outline, size: 18, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Text(user?.email ?? '-', style: TextStyle(color: AppColors.muted)),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    FilledButton(onPressed: _saveProfile, child: const Text('Save name')),
                    OutlinedButton(onPressed: _changePassword, child: const Text('Change password')),
                  ]),
                ]),
              ),
              const SizedBox(height: 24),

              sectionTitle('AI settings'),
              const SizedBox(height: 10),
              settings.when(
                loading: () => const Panel(child: SkeletonBox(height: 160)),
                error: (e, _) => ErrorPanel(error: e, onRetry: () => ref.invalidate(appSettingsProvider)),
                data: (s) => Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.smart_toy_outlined, size: 18, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Text('Provider: ${s.provider}', style: TextStyle(color: AppColors.muted)),
                    ]),
                    const SizedBox(height: 14),
                    AppDropdown<String>(
                      label: 'Model',
                      value: s.model.isEmpty ? '' : s.model,
                      items: [
                        DropdownMenuItem(value: '', child: Text('Server default (${s.defaultModel})')),
                        for (final m in s.availableModels) DropdownMenuItem(value: m, child: Text(m)),
                      ],
                      onChanged: (v) => ref
                          .read(appSettingsProvider.notifier)
                          .save(AppSettings(
                              responseStyle: s.responseStyle, temperature: s.temperature, model: v ?? '',
                              historyMessages: s.historyMessages, provider: s.provider,
                              defaultModel: s.defaultModel, availableModels: s.availableModels)),
                    ),
                    const SizedBox(height: 14),
                    AppDropdown<String>(
                      label: 'Response style',
                      value: s.responseStyle,
                      items: const [
                        DropdownMenuItem(value: 'concise', child: Text('Concise')),
                        DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
                        DropdownMenuItem(value: 'detailed', child: Text('Detailed')),
                      ],
                      onChanged: (v) => ref
                          .read(appSettingsProvider.notifier)
                          .save(AppSettings(
                              responseStyle: v ?? s.responseStyle, temperature: s.temperature, model: s.model,
                              historyMessages: s.historyMessages, provider: s.provider,
                              defaultModel: s.defaultModel, availableModels: s.availableModels)),
                    ),
                    const SizedBox(height: 14),
                    Text('Temperature: ${s.temperature.toStringAsFixed(2)}',
                        style: TextStyle(color: AppColors.muted)),
                    Slider(
                      value: s.temperature,
                      onChanged: (v) => ref.read(appSettingsProvider.notifier).save(AppSettings(
                          responseStyle: s.responseStyle, temperature: v, model: s.model,
                          historyMessages: s.historyMessages, provider: s.provider,
                          defaultModel: s.defaultModel, availableModels: s.availableModels)),
                      onChangeEnd: (v) => ref.read(appSettingsProvider.notifier).save(AppSettings(
                          responseStyle: s.responseStyle, temperature: v, model: s.model,
                          historyMessages: s.historyMessages, provider: s.provider,
                          defaultModel: s.defaultModel, availableModels: s.availableModels)),
                      min: 0,
                      max: 1,
                      divisions: 20,
                    ),
                    Text('Context: last ${s.historyMessages} messages',
                        style: TextStyle(color: AppColors.muted)),
                    Slider(
                      value: s.historyMessages.toDouble(),
                      min: 4,
                      max: 60,
                      divisions: 14,
                      onChangeEnd: (v) => ref.read(appSettingsProvider.notifier).save(AppSettings(
                          responseStyle: s.responseStyle, temperature: s.temperature, model: s.model,
                          historyMessages: v.round(), provider: s.provider,
                          defaultModel: s.defaultModel, availableModels: s.availableModels)),
                      onChanged: (_) {},
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 24),

              sectionTitle('Appearance'),
              const SizedBox(height: 10),
              Panel(
                child: Row(children: [
                  Icon(Icons.dark_mode_outlined, size: 18, color: AppColors.muted),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Theme')),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16), label: Text('Dark')),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16), label: Text('Light')),
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 16), label: Text('System')),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                  ),
                ]),
              ),
              const SizedBox(height: 24),

              sectionTitle('Integrations'),
              const SizedBox(height: 10),
              Panel(
                child: github.when(
                  loading: () => const SkeletonBox(height: 24),
                  error: (e, _) => Text(toApiException(e).message),
                  data: (g) => Row(children: [
                    Icon(Icons.hub_outlined, size: 18, color: AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(g.connected ? 'GitHub connected as ${g.login}' : 'GitHub not connected')),
                    TextButton(onPressed: () => context.go('/github'), child: const Text('Manage')),
                  ]),
                ),
              ),
              const SizedBox(height: 24),

              sectionTitle('Security'),
              const SizedBox(height: 10),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.security, size: 18, color: AppColors.muted),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Signing out everywhere ends every session, including this device.')),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    OutlinedButton.icon(
                        onPressed: () => _confirmSignOut(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out')),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: BorderSide(color: AppColors.danger)),
                      onPressed: () => _confirmSignOut(everywhere: true),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out everywhere'),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}