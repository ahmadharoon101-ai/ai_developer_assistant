import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

const _ext = {
  'python': 'py', 'dart': 'dart', 'javascript': 'js', 'typescript': 'ts', 'java': 'java',
  'c#': 'cs', 'csharp': 'cs', 'cs': 'cs', 'c++': 'cpp', 'cpp': 'cpp', 'go': 'go', 'rust': 'rs',
  'bash': 'sh', 'shell': 'sh', 'sh': 'sh', 'json': 'json', 'yaml': 'yaml', 'sql': 'sql',
  'html': 'html', 'css': 'css', 'markdown': 'md', 'md': 'md',
};

String extensionFor(String language) => _ext[language.trim().toLowerCase()] ?? 'txt';

/// Saves a text file through the platform's save/download mechanism.
Future<void> exportText(String baseName, String ext, String text) async {
  await FileSaver.instance.saveFile(
    name: baseName,
    bytes: Uint8List.fromList(utf8.encode(text)),
    ext: ext,
    mimeType: MimeType.other,
  );
}

class CodeSnippet {
  const CodeSnippet(this.language, this.code);
  final String language;
  final String code;
}

/// First fenced code block in a markdown string, or null.
CodeSnippet? firstCodeBlock(String markdown) {
  final m = RegExp(r'```([^\n`]*)\n([\s\S]*?)```').firstMatch(markdown);
  if (m == null) return null;
  return CodeSnippet(m.group(1)!.trim(), m.group(2)!.trimRight());
}
