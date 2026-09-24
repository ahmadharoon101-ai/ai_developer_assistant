import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/panel.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../domain/chat_models.dart';
import 'chat_controller.dart';
import '../../projects/presentation/projects_controller.dart';
import 'widgets/composer.dart';
import 'widgets/conversation_list.dart';
import 'widgets/message_view.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Follow the stream only if the reader hasn't scrolled away.
  void _followIfNearBottom() {
    if (!_scroll.hasClients) return;
    final near = _scroll.position.maxScrollExtent - _scroll.position.pixels < 180;
    if (!near) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChatState>(chatControllerProvider, (prev, next) {
      if (prev?.activeId != next.activeId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      } else {
        _followIfNearBottom();
      }
    });

    final chat = ref.watch(chatControllerProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final messages = chat.activeMessages;
    final lastAiIndex = messages.lastIndexWhere((m) => m.role == MessageRole.ai);
    final title = chat.activeId == null
        ? 'New chat'
        : (chat.conversations.where((c) => c.id == chat.activeId).firstOrNull?.title ??
            'Conversation');

    final main = Column(
      children: [
        _Toolbar(title: title, showHistory: !wide),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? (chat.isLoadingMessages
                  ? const Center(child: CircularProgressIndicator())
                  : const _EmptyChat())
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: MessageView(
                          message: messages[i], isLastAi: i == lastAiIndex),
                    ),
                  ),
                ),
        ),
        const Composer(),
      ],
    );

    if (!wide) return main;
    return Row(children: [
      const SizedBox(width: 272, child: ConversationList()),
      VerticalDivider(width: 1, color: AppColors.border),
      Expanded(child: main),
    ]);
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.title, required this.showHistory});
  final String title;
  final bool showHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(chatControllerProvider.select((s) => s.projectId));
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
    final current = projects.where((p) => p.id == projectId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        if (showHistory)
          IconButton(
            tooltip: 'Conversations',
            icon: const Icon(Icons.history),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: AppColors.sidebar,
              isScrollControlled: true,
              builder: (ctx) => SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.75,
                child: ConversationList(onSelected: () => Navigator.pop(ctx)),
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Project context',
          color: AppColors.surfaceHigh,
          onSelected: (v) => ref
              .read(chatControllerProvider.notifier)
              .setProject(v.isEmpty ? null : v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: '', child: Text('No project context')),
            for (final p in projects) PopupMenuItem(value: p.id, child: Text(p.name)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: current == null ? AppColors.border : AppColors.accent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.folder_outlined, size: 16,
                  color: current == null ? AppColors.muted : AppColors.accent),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(current?.name ?? 'No project',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ),
              Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _EmptyChat extends ConsumerWidget {
  const _EmptyChat();

  static const _starters = [
    ('Explain this error', 'Why am I getting this FastAPI error?'),
    ('Review my code', 'Review my code for bugs and code smells.'),
    ('Generate an endpoint', 'Generate a FastAPI endpoint for user registration.'),
    ('Write tests', 'Write unit tests for my authentication service.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What are you working on?',
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Paste an error, describe a feature, or ask about your code.',
                  style: t.bodyMedium?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 20),
              ResponsiveGrid(minItemWidth: 260, children: [
                for (final s in _starters)
                  Panel(
                    padding: const EdgeInsets.all(14),
                    onTap: () =>
                        ref.read(chatControllerProvider.notifier).send(s.$2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.$1,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(s.$2,
                            style: t.bodySmall?.copyWith(color: AppColors.muted)),
                      ],
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
