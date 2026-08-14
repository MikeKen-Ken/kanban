import 'dart:collection';

/// 调度工作台的有界内存日志。
///
/// 同时限制行数和字符数，避免单行异常输出或长时间批次无限占用内存。
class AgentDispatchLogBuffer {
  AgentDispatchLogBuffer({
    this.maxLines = 3000,
    this.maxCharacters = 2 * 1024 * 1024,
  })  : assert(maxLines > 0),
        assert(maxCharacters > 0);

  final int maxLines;
  final int maxCharacters;
  final ListQueue<String> _lines = ListQueue<String>();
  int _characterCount = 0;

  int get length => _lines.length;

  bool get isEmpty => _lines.isEmpty;

  String get text => _lines.join('\n');

  void replaceWith(String value) {
    clear();
    if (value.isEmpty) return;
    addLines(value.split(RegExp(r'\r?\n')));
  }

  void addLines(Iterable<String> lines) {
    for (var line in lines) {
      if (line.length > maxCharacters) {
        line = line.substring(line.length - maxCharacters);
      }
      _lines.addLast(line);
      _characterCount += line.length;
      _trim();
    }
  }

  void clear() {
    _lines.clear();
    _characterCount = 0;
  }

  void _trim() {
    while (_lines.length > maxLines ||
        (_characterCount + _separatorCharacters) > maxCharacters) {
      if (_lines.length <= 1) break;
      _characterCount -= _lines.removeFirst().length;
    }
  }

  int get _separatorCharacters => _lines.isEmpty ? 0 : _lines.length - 1;
}
