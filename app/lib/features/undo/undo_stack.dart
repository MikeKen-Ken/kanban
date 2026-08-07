import 'dart:collection';

typedef UndoCallback = Future<void> Function();

class UndoEntry {
  const UndoEntry({
    required this.label,
    required this.undo,
    required this.redo,
  });

  final String label;
  final UndoCallback undo;
  final UndoCallback redo;
}

/// 设备本机的有限撤销/重做栈；动作仍需通过正常持久化入口写回并同步。
class UndoStack {
  UndoStack({this.capacity = 20});

  final int capacity;
  final Queue<UndoEntry> _undoEntries = Queue<UndoEntry>();
  final Queue<UndoEntry> _redoEntries = Queue<UndoEntry>();
  bool _isApplying = false;

  bool get canUndo => _undoEntries.isNotEmpty && !_isApplying;
  bool get canRedo => _redoEntries.isNotEmpty && !_isApplying;
  String? get nextUndoLabel =>
      _undoEntries.isEmpty ? null : _undoEntries.last.label;
  String? get nextRedoLabel =>
      _redoEntries.isEmpty ? null : _redoEntries.last.label;

  /// 兼容旧调用方：下一笔可撤销操作的标签。
  String? get nextLabel => nextUndoLabel;

  void push(UndoEntry entry) {
    if (_isApplying || capacity < 1) return;
    _undoEntries.addLast(entry);
    _redoEntries.clear();
    while (_undoEntries.length > capacity) {
      _undoEntries.removeFirst();
    }
  }

  Future<bool> undo() async {
    if (!canUndo) return false;
    final entry = _undoEntries.removeLast();
    _isApplying = true;
    try {
      await entry.undo();
      _redoEntries.addLast(entry);
      while (_redoEntries.length > capacity) {
        _redoEntries.removeFirst();
      }
      return true;
    } finally {
      _isApplying = false;
    }
  }

  Future<bool> redo() async {
    if (!canRedo) return false;
    final entry = _redoEntries.removeLast();
    _isApplying = true;
    try {
      await entry.redo();
      _undoEntries.addLast(entry);
      while (_undoEntries.length > capacity) {
        _undoEntries.removeFirst();
      }
      return true;
    } finally {
      _isApplying = false;
    }
  }

  void clear() {
    _undoEntries.clear();
    _redoEntries.clear();
  }
}
