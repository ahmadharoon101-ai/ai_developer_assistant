import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/brand_mark.dart';
import '../../../../shared/widgets/toast.dart';
import '../../domain/chat_models.dart';
import '../chat_controller.dart';
import '../../../../shared/components/rich_content.dart';

class MessageView extends ConsumerWidget {
  const MessageView({super.key, required this.message, this.isLastAi = false});
  final ChatMessage message;
  final bool isLastAi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (message.role) {
      case MessageRole.user:
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.images.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: [
                          for (final img in message.images)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(img.bytes,
                                  width: 96, height: 96, fit: BoxFit.cover),
                            ),
                        ],
                      ),
                    ),
                  if (message.content.isNotEmpty) SelectableText(message.content),
                ],
              ),
            ),
          ),
        );
      case MessageRole.tool:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 40),
          child: Row(children: [
            if (message.isError)
              Icon(Icons.error_outline, size: 15, color: AppColors.danger)
            else if (message.streaming)
              const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.6))
            else
              Icon(Icons.check, size: 15, color: AppColors.success),
            const SizedBox(width: 10),
            Flexible(
              child: Text(message.content,
                  style: AppTheme.mono(
                      size: 12.5,
                      color: message.isError ? AppColors.danger : AppColors.muted)),
            ),
          ]),
        );
      case MessageRole.ai:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                  padding: EdgeInsets.only(top: 2), child: BrandMark(size: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichContent(content: message.content, streaming: message.streaming),
                    if (!message.streaming)
                      _Actions(message: message, isLastAi: isLastAi),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.message, required this.isLastAi});
  final ChatMessage message;
  final bool isLastAi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(chatControllerProvider.select((s) => s.isStreaming));
    Widget btn(IconData i, String tip, VoidCallback? f) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          color: AppColors.muted,
          icon: Icon(i),
          onPressed: f,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        btn(Icons.copy_rounded, 'Copy response', () async {
          await Clipboard.setData(ClipboardData(text: message.content));
          if (context.mounted) showToast(context, 'Response copied');
        }),
        if (isLastAi)
          btn(Icons.refresh_rounded, 'Regenerate response',
              busy ? null : () => ref.read(chatControllerProvider.notifier).regenerate()),
        btn(Icons.lightbulb_outline, 'Explain in more detail', busy
            ? null
            : () => ref
                .read(chatControllerProvider.notifier)
                .send('Explain your last answer in more detail, step by step.')),
      ]),
    );
  }
}

