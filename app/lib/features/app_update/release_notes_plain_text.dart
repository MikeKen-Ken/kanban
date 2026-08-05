/// 将 GitHub Release 说明转为适合软件内展示的纯文本。
///
/// Atom 源为 HTML；REST API 源多为 Markdown。两者都做轻量规范化。
String releaseNotesToPlainText(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';

  if (_looksLikeHtml(trimmed)) {
    return _htmlToPlainText(trimmed);
  }
  return _normalizePlainOrMarkdown(trimmed);
}

bool _looksLikeHtml(String text) {
  return RegExp(
    r'</?(?:p|h[1-6]|ul|ol|li|br|div|span|a|strong|em|tt|code|pre)\b',
    caseSensitive: false,
  ).hasMatch(text);
}

String _htmlToPlainText(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
  s = s.replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n');
  s = s.replaceAll(RegExp(r'</li>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</div>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</tr>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ');
  s = s.replaceAllMapped(
    RegExp(
      r'<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    ),
    (match) {
      final inner = _stripTags(match.group(2)!).trim();
      return inner.isEmpty ? match.group(1)! : inner;
    },
  );
  s = _stripTags(s);
  s = _decodeHtmlEntities(s);
  return _collapseBlankLines(s).trim();
}

String _normalizePlainOrMarkdown(String text) {
  var s = text;
  // 去掉常见 Markdown 标题标记，保留正文
  s = s.replaceAllMapped(
    RegExp(r'^#{1,6}\s+', multiLine: true),
    (_) => '',
  );
  return _collapseBlankLines(s).trim();
}

String _stripTags(String input) =>
    input.replaceAll(RegExp(r'<[^>]+>'), '');

String _decodeHtmlEntities(String input) {
  var s = input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    if (code == null) return m.group(0)!;
    return String.fromCharCode(code);
  });
  s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    if (code == null) return m.group(0)!;
    return String.fromCharCode(code);
  });
  // &amp; 最后处理，避免二次解码
  return s.replaceAll('&amp;', '&');
}

String _collapseBlankLines(String input) {
  return input
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
}
