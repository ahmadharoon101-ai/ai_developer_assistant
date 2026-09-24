import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/search_field.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../chat_controller.dart';

class ConversationList extends ConsumerStatefulWidget {
  const ConversationList({super.key, this.onSelected});
  final VoidCallback? onSelected;

  @override
  ConsumerState<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends ConsumerState<ConversationList> {
  String _query = '';

  Future<void> _confirmDelete(String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete conversation?'),
        content: Text('"$title" will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(chatControllerProvider.notifier).deleteConversation(id);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final items = chat.conversations
        .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    Widget body;
    if (chat.isLoadingList && chat.conversations.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          SkeletonBox(height: 34), SizedBox(height: 10), SkeletonBox(height: 34), SizedBox(height: 10), SkeletonBox(height: 34),
        ]),
      );
    } else if (chat.listError != null && chat.conversations.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(chat.listError!, style: TextStyle(color: AppColors.danger)),
          TextButton(
              onPressed: () => ref.read(chatControllerProvider.notifier).loadConversations(),
              child: const Text('Retry')),
        ]),
      );
    } else if (items.isEmpty) {
      body = Center(
          child: Text(_query.isEmpty ? 'No conversations yet.' : 'No conversations match.',
              style: TextStyle(color: AppColors.muted)));
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final c = items[i];
          final selected = c.id == chat.activeId;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Material(
              color: selected ? AppColors.surfaceHigh : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(c.updated, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                trailing: IconButton(
                  tooltip: 'Delete',
                  iconSize: 18,
                  color: AppColors.muted,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(c.id, c.title),
                ),
                onTap: () {
                  ref.read(chatControllerProvider.notifier).select(c.id);
                  widget.onSelected?.call();
                },
              ),
            ),
          );
        },
      );
    }

    return Container(
      color: AppColors.sidebar,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  ref.read(chatControllerProvider.notifier).newConversation();
                  widget.onSelected?.call();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New chat'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SearchField(hint: 'Search conversations', onChanged: (v) => setState(() => _query = v)),
          ),
          const SizedBox(height: 8),
          Expanded(child: body),
        ],
      ),
    );
  }
}
