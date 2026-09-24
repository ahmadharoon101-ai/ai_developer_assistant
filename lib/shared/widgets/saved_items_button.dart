import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../data/saved_repository.dart';
import 'toast.dart';

/// History icon that lists items the user saved for [kind] and lets them reload or delete one.
class SavedItemsButton extends ConsumerWidget {
  const SavedItemsButton({super.key, required this.kind, required this.onLoad});
  final String kind;
  final void Function(Map<String, dynamic> payload) onLoad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        builder: (ctx) => _SavedSheet(kind: kind, onLoad: (p) {
          Navigator.pop(ctx);
          onLoad(p);
        }),
      ),
      icon: const Icon(Icons.bookmarks_outlined, size: 18),
      label: const Text('Saved'),
    );
  }
}

class _SavedSheet extends ConsumerStatefulWidget {
  const _SavedSheet({required this.kind, required this.onLoad});
  final String kind;
  final void Function(Map<String, dynamic>) onLoad;

  @override
  ConsumerState<_SavedSheet> createState() => _SavedSheetState();
}

class _SavedSheetState extends ConsumerState<_SavedSheet> {
  late Future<List<SavedItem>> _future = ref.read(savedRepositoryProvider).list(widget.kind);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: FutureBuilder<List<SavedItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(toApiException(snap.error!).message));
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(child: Text('Nothing saved yet.', style: TextStyle(color: AppColors.muted)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final it = items[i];
              return ListTile(
                title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(relativeTime(it.createdAt), style: TextStyle(color: AppColors.muted)),
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await ref.read(savedRepositoryProvider).delete(it.id);
                      setState(() => _future = ref.read(savedRepositoryProvider).list(widget.kind));
                    } catch (e) {
                      if (context.mounted) showToast(context, toApiException(e).message);
                    }
                  },
                ),
                onTap: () => widget.onLoad(it.payload),
              );
            },
          );
        },
      ),
    );
  }
}
