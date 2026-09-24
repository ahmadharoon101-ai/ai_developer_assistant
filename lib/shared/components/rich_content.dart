import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'code_block.dart';


class _Segment {
  _Segment.text(this.body)
      : isCode = false,
        language = '';
  _Segment.code(this.body, this.language) : isCode = true;
  final String body;
  final bool isCode;
  final String language;
}

List<_Segment> _parse(String s) {
  final out = <_Segment>[];
  final buf = StringBuffer();
  var inCode = false;
  var lang = '';

  void flushText() {
    final t = buf.toString().trim();
    if (t.isNotEmpty) out.add(_Segment.text(t));
    buf.clear();
  }

  for (final line in s.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      if (!inCode) {
        flushText();
        inCode = true;
        lang = line.trim().substring(3).trim();
      } else {
        out.add(_Segment.code(buf.toString(), lang));
        buf.clear();
        inCode = false;
      }
      continue;
    }
    buf.writeln(line);
  }
  if (inCode) {
    out.add(_Segment.code(buf.toString(), lang)); // still streaming
  } else {
    flushText();
  }
  return out;
}

/// Renders headings, bullets, **bold**, `inline code` and fenced code blocks.
class RichContent extends StatelessWidget {
  const RichContent({super.key, required this.content, this.streaming = false});
  final String content;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final segs = _parse(content);
    final t = Theme.of(context).textTheme;
    final children = <Widget>[];

    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      if (s.isCode) {
        children.add(CodeBlock(code: s.body, language: s.language, fileName: 'snippet'));
        continue;
      }
      for (final line in s.body.split('\n')) {
        if (line.trim().isEmpty) {
          children.add(const SizedBox(height: 6));
        } else if (line.startsWith('### ')) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(line.substring(4),
                style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: AppColors.accent)),
          ));
        } else if (line.startsWith('- ')) {
          children.add(Padding(
            padding: const EdgeInsets.only(left: 6, top: 2, bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 10),
                child: Icon(Icons.circle, size: 5, color: AppColors.muted),
              ),
              Expanded(child: _inline(line.substring(2), t.bodyMedium!)),
            ]),
          ));
        } else {
          children.add(_inline(line, t.bodyMedium!));
        }
      }
    }
    if (streaming) {
      children.add(Text('▍', style: AppTheme.mono(color: AppColors.accent)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _inline(String text, TextStyle base) {
    final style = base.copyWith(height: 1.55);
    final spans = <InlineSpan>[];
    final re = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*)');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final tok = m.group(0)!;
      if (tok.startsWith('`')) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: AppTheme.mono(size: 13, color: AppColors.teal)
              .copyWith(backgroundColor: AppColors.surfaceHigh),
        ));
      } else {
        spans.add(TextSpan(
            text: tok.substring(2, tok.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700)));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}
