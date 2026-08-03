import 'dart:collection';

typedef UndoCallback = Future<void> Function();

class UndoEntry {
  const UndoEntry({
    required this.label,
    required this.undo,
  });

  final String label;
  final UndoCallback undo;
}

/// 设备本机的有限撤销栈；撤销动作仍需通过正常持久化入口写回并同步。
class UndoStack {
  UndoStack({this.capacity = 20});

  final int capacity;
  final Queue<UndoEntry> _entries = Queue<UndoEntry>();
  bool _isUndoing = false;

  bool get canUndo => _entries.isNotEmpty && !_isUndoing;
  String? get nextLabel => _entries.isEmpty ? null : _entries.last.label;

  void push(UndoEntry entry) {
    if (_isUndoing || capacity < 1) return;
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  Future<bool> undo() async {
    if (!canUndo) return false;
    final entry = _entries.removeLast();
    _isUndoing = true;
    try {
      await entry.undo();
      return true;
    } finally {
      _isUndoing = false;
    }
  }

  void clear() => _entries.clear();
}
