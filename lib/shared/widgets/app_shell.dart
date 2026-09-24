import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/auth_controller.dart';
import 'brand_mark.dart';
import 'nav_items.dart';

/// Responsive shell: sidebar (desktop), rail (tablet), drawer + bottom bar (mobile).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  int _indexFor(String location) =>
      navItems.indexWhere((i) => location.startsWith(i.path));

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFor(location);
    final width = MediaQuery.sizeOf(context).width;

    void go(int i) => context.go(navItems[i].path);

    Widget body;
    if (width >= 1000) {
      body = Row(children: [
        _Sidebar(selected: index, onSelect: go),
        VerticalDivider(width: 1, color: AppColors.border),
        Expanded(child: widget.child),
      ]);
    } else if (width >= 640) {
      body = Row(children: [
        NavigationRail(
          backgroundColor: AppColors.sidebar,
          selectedIndex: index < 0 ? null : index,
          onDestinationSelected: go,
          labelType: NavigationRailLabelType.none,
          leading: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: BrandMark(size: 34),
          ),
          destinations: [
            for (final i in navItems)
              NavigationRailDestination(
                icon: Tooltip(message: i.label, child: Icon(i.icon)),
                label: Text(i.label),
              ),
          ],
        ),
        VerticalDivider(width: 1, color: AppColors.border),
        Expanded(child: widget.child),
      ]);
    } else {
      body = widget.child;
    }

    final compact = width < 640;
    final title = index < 0 ? 'AI Developer Assistant' : navItems[index].label;

    return CallbackShortcuts(
      bindings: {
        // Ctrl/Cmd+K jumps to AI Chat; Ctrl/Cmd+1..0 jump between sections.
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            context.go('/chat'),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            context.go('/chat'),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            go(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            go(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            go(2),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: _scaffoldKey,
          appBar: compact
              ? AppBar(
                  title: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  leading: IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: 'Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                )
              : null,
          drawer: compact
              ? Drawer(
                  backgroundColor: AppColors.sidebar,
                  child: SafeArea(
                    child: _SidebarContent(
                      selected: index,
                      onSelect: (i) {
                        Navigator.of(context).pop();
                        go(i);
                      },
                    ),
                  ),
                )
              : null,
          bottomNavigationBar: compact
              ? NavigationBar(
                  backgroundColor: AppColors.sidebar,
                  selectedIndex: index == 4 ? 3 : (index >= 0 && index < 3 ? index : 4),
                  onDestinationSelected: (i) => i == 4
                      ? _scaffoldKey.currentState?.openDrawer()
                      : go(i == 3 ? 4 : i),
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.space_dashboard_outlined),
                        label: 'Dashboard'),
                    NavigationDestination(
                        icon: Icon(Icons.forum_outlined), label: 'Chat'),
                    NavigationDestination(
                        icon: Icon(Icons.folder_copy_outlined),
                        label: 'Projects'),
                    NavigationDestination(
                        icon: Icon(Icons.bug_report_outlined),
                        label: 'Debug'),
                    NavigationDestination(
                        icon: Icon(Icons.apps), label: 'More'),
                  ],
                )
              : null,
          body: SafeArea(child: body),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: AppColors.sidebar,
      child: _SidebarContent(selected: selected, onSelect: onSelect),
    );
  }
}

class _SidebarContent extends ConsumerWidget {
  const _SidebarContent({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          child: Row(children: [
            const BrandMark(size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Text('AI Developer\nAssistant',
                  style: t.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (var i = 0; i < navItems.length; i++)
                _NavTile(
                    item: navItems[i],
                    selected: i == selected,
                    onTap: () => onSelect(i)),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surfaceHigh,
            child: Text(
              (user?.name.isNotEmpty ?? false)
                  ? user!.name[0].toUpperCase()
                  : '?',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
          title: Text(user?.name ?? 'Signed out',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(user?.email ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: AppColors.muted)),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile(
      {required this.item, required this.selected, required this.onTap});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: selected ? AppColors.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(item.icon,
                  size: 20,
                  color: selected ? AppColors.accent : AppColors.muted),
              const SizedBox(width: 12),
              Text(item.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppColors.text : AppColors.muted,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}
