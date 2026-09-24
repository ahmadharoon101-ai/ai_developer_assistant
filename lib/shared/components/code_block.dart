import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/file_export.dart';
import '../widgets/toast.dart';

const _supported = {
  'python', 'dart', 'javascript', 'typescript', 'java', 'cs', 'cpp', 'go',
  'rust', 'bash', 'json', 'yaml', 'sql', 'xml', 'css', 'plaintext',
};
const _aliases = {
  'py': 'python', 'js': 'javascript', 'ts': 'typescript', 'c#': 'cs',
  'csharp': 'cs', 'c++': 'cpp', 'sh': 'bash', 'shell': 'bash', 'zsh': 'bash',
  'yml': 'yaml', 'html': 'xml', 'golang': 'go', 'rs': 'rust',
};

String normalizeLanguage(String raw) {
  final l = raw.trim().toLowerCase();
  final mapped = _aliases[l] ?? l;
  return _supported.contains(mapped) ? mapped : 'plaintext';
}

class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language = '',
    this.onApply,
    this.applyLabel = 'Apply',
    this.fileName = 'code',
    this.maxLines,
  });

  final String code;
  final String language;
  final VoidCallback? onApply;
  final String applyLabel;
  final String fileName;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final lang = normalizeLanguage(language);
    final theme = {
      ...atomOneDarkTheme,
      'root': const TextStyle(
          backgroundColor: Colors.transparent, color: Color(0xFFABB2BF)),
    };
    var body = code.trimRight();
    String? truncated;
    if (maxLines != null) {
      final lines = body.split('\n');
      if (lines.length > maxLines!) {
        truncated = 'Showing first $maxLines of ${lines.length} lines';
        body = lines.take(maxLines!).join('\n');
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.codeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(children: [
              Text(language.isEmpty ? 'code' : language,
                  style: AppTheme.mono(size: 12, color: AppColors.muted)),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 17),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: body));
                  if (context.mounted) showToast(context, 'Code copied');
                },
              ),
              IconButton(
                tooltip: 'Download',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.download_rounded, size: 17),
                onPressed: () async {
                  try {
                    await exportText(fileName, extensionFor(language), code);
                    if (context.mounted) showToast(context, 'File saved');
                  } catch (_) {
                    if (context.mounted) {
                      showToast(context, 'Could not save the file on this device.');
                    }
                  }
                },
              ),
              if (onApply != null)
                TextButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(applyLabel),
                ),
            ]),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              body.isEmpty ? ' ' : body,
              language: lang,
              theme: theme,
              padding: const EdgeInsets.all(14),
              textStyle: AppTheme.mono(size: 13),
            ),
          ),
          if (truncated != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(truncated,
                  style: AppTheme.mono(size: 11.5, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }
}
