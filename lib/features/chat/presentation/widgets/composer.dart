import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/panel.dart';
import '../../../../shared/widgets/state_widgets.dart';
import '../../../../shared/widgets/toast.dart';
import '../../domain/chat_models.dart';
import '../chat_controller.dart';

const _imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif'];
const _mimeByExt = {
  'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
  'webp': 'image/webp', 'gif': 'image/gif',
};
const _maxImageBytes = 6 * 1024 * 1024;

class Composer extends ConsumerStatefulWidget {
  const Composer({super.key});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _listening = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    if (_listening) _speech.stop();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty && ref.read(chatControllerProvider).pendingImages.isEmpty) return;
    ref.read(chatControllerProvider.notifier).send(text);
    _controller.clear();
    _focus.requestFocus();
  }

  // ---- attachments ----------------------------------------------------------

  Future<void> _attachFile() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    if (_imageExtensions.contains(ext)) {
      _addImageBytes(file.bytes!, file.name, _mimeByExt[ext]!);
      return;
    }
    String text;
    try {
      text = String.fromCharCodes(file.bytes!);
    } catch (_) {
      if (mounted) showToast(context, "That file doesn't look like text — try an image instead.");
      return;
    }
    if (text.length > 20000) text = '${text.substring(0, 20000)}\n… (truncated)';
    _insertAtCursor('\n```${_langFor(ext)}\n// ${file.name}\n$text\n```\n');
  }

  Future<void> _attachImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _imageExtensions,
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = _mimeByExt[ext];
    if (mime == null) {
      if (mounted) showToast(context, 'Unsupported image type.');
      return;
    }
    _addImageBytes(file.bytes!, file.name, mime);
  }

  void _addImageBytes(Uint8List bytes, String name, String mime) {
    if (bytes.length > _maxImageBytes) {
      showToast(context, 'That image is too large (max 6 MB).');
      return;
    }
    final error = ref
        .read(chatControllerProvider.notifier)
        .addPendingImage(ImageAttachment(bytes: bytes, mime: mime, name: name));
    if (error != null && mounted) showToast(context, error);
  }

  Future<void> _attachCode() async {
    final code = TextEditingController();
    final language = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Attach code'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: language, decoration: fieldDecoration('Language (optional)')),
            const SizedBox(height: 12),
            CodeField(controller: code, label: 'Code', minLines: 6, maxLines: 14),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Attach')),
        ],
      ),
    );
    if (ok != true || code.text.trim().isEmpty) return;
    _insertAtCursor('\n```${language.text.trim()}\n${code.text}\n```\n');
  }

  void _insertAtCursor(String snippet) {
    final sel = _controller.selection;
    final text = _controller.text;
    final insertAt = sel.start >= 0 ? sel.start : text.length;
    final next = text.replaceRange(insertAt, sel.end >= 0 ? sel.end : text.length, snippet);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: insertAt + snippet.length),
    );
    _focus.requestFocus();
  }

  String _langFor(String ext) => const {
        'py': 'python', 'dart': 'dart', 'js': 'javascript', 'ts': 'typescript', 'java': 'java',
        'cs': 'csharp', 'cpp': 'cpp', 'c': 'c', 'go': 'go', 'rs': 'rust', 'json': 'json',
        'yaml': 'yaml', 'yml': 'yaml', 'md': 'markdown', 'sh': 'bash', 'sql': 'sql',
      }[ext] ??
      '';

  // ---- voice input ------------------------------------------------------------

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onError: (e) {
          if (mounted) showToast(context, 'Voice input error: ${e.errorMsg}');
          setState(() => _listening = false);
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
      );
      if (!_speechReady) {
        if (mounted) {
          showToast(context,
              "Voice input isn't available here — it needs mic/speech permission and platform "
              'support (works on Android, iOS, macOS and web; desktop Windows/Linux support '
              'depends on your Flutter/plugin version).');
        }
        return;
      }
    }
    final baseText = _controller.text;
    final sep = baseText.isEmpty || baseText.endsWith(' ') ? '' : ' ';
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _controller.value = TextEditingValue(
          text: baseText + sep + result.recognizedWords,
          selection: TextSelection.collapsed(
              offset: (baseText + sep + result.recognizedWords).length),
        );
      },
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final streaming = ref.watch(chatControllerProvider.select((s) => s.isStreaming));
    final pendingImages = ref.watch(chatControllerProvider.select((s) => s.pendingImages));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pendingImages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < pendingImages.length; i++)
                        _ImageChip(
                          image: pendingImages[i],
                          onRemove: () =>
                              ref.read(chatControllerProvider.notifier).removePendingImage(i),
                        ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _listening ? AppColors.accent : AppColors.border,
                      width: _listening ? 1.4 : 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Attach',
                      icon: Icon(Icons.add_circle_outline, color: AppColors.muted),
                      color: AppColors.surfaceHigh,
                      onSelected: (v) => switch (v) {
                        'file' => _attachFile(),
                        'code' => _attachCode(),
                        'image' => _attachImage(),
                        _ => null,
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'file',
                            child: ListTile(
                                leading: Icon(Icons.attach_file), title: Text('File'))),
                        PopupMenuItem(
                            value: 'code',
                            child: ListTile(
                                leading: Icon(Icons.data_object), title: Text('Code'))),
                        PopupMenuItem(
                            value: 'image',
                            child: ListTile(
                                leading: Icon(Icons.image_outlined), title: Text('Image'))),
                      ],
                    ),
                    Expanded(
                      child: Focus(
                        // Enter sends, Shift+Enter inserts a newline.
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _send();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 8,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: _listening
                                ? 'Listening…'
                                : 'Ask about code, paste an error, or describe a feature…',
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _listening ? 'Stop listening' : 'Voice input',
                      icon: Icon(_listening ? Icons.mic : Icons.mic_none_rounded,
                          color: _listening ? AppColors.accent : AppColors.muted),
                      onPressed: _toggleListening,
                    ),
                    const SizedBox(width: 2),
                    streaming
                        ? IconButton.filledTonal(
                            tooltip: 'Stop generating',
                            icon: const Icon(Icons.stop_rounded),
                            onPressed: () => ref.read(chatControllerProvider.notifier).stop(),
                          )
                        : IconButton.filled(
                            tooltip: 'Send',
                            icon: const Icon(Icons.arrow_upward),
                            onPressed: _send,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageChip extends StatelessWidget {
  const _ImageChip({required this.image, required this.onRemove});
  final ImageAttachment image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.memory(image.bytes, width: 32, height: 32, fit: BoxFit.cover),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 100),
          child: Text(image.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ),
        InkWell(
          onTap: onRemove,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.close, size: 14, color: AppColors.muted),
          ),
        ),
      ]),
    );
  }
}
