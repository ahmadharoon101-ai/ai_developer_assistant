import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

void main() {
  runApp(const ProviderScope(child: AiDeveloperAssistantApp()));
}

class AiDeveloperAssistantApp extends ConsumerStatefulWidget {
  const AiDeveloperAssistantApp({super.key});

  @override
  ConsumerState<AiDeveloperAssistantApp> createState() => _AiDeveloperAssistantAppState();
}

class _AiDeveloperAssistantAppState extends ConsumerState<AiDeveloperAssistantApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Only matters when following the OS setting; forces a rebuild so the
    // live palette (AppColors._current) is recomputed for the new brightness.
    if (ref.read(themeModeProvider) == ThemeMode.system) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final resolved = mode == ThemeMode.system
        ? platformBrightness
        : (mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
    AppColors.apply(resolved);

    return MaterialApp.router(
      title: 'AI Developer Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: mode,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
