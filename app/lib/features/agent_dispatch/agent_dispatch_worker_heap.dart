/// 无法探测物理内存时的 Node 堆上限（MB）。
const kWorkerNodeFallbackHeapMb = 8192;

/// 避免单进程在超大内存机器上吃光全部 RAM（约 64GB 机器的 75%）。
const kWorkerNodeMaxHeapMb = 49152;

/// 过小则仍会轻易撞上 Cursor SDK 默认约 4GB 的同类 OOM。
const kWorkerNodeMinHeapMb = 4096;

/// 按本机物理内存选择 Worker 的 `--max-old-space-size`（MB）。
///
/// 这是 V8 堆**上限**，不是启动时立刻占用。用户可通过
/// `KANBAN_WORKER_HEAP_MB` 或已有的 `--max-old-space-size` 覆盖。
int chooseWorkerNodeHeapMb({
  int? totalPhysicalMb,
  int? explicitHeapMb,
}) {
  if (explicitHeapMb != null && explicitHeapMb > 0) {
    return explicitHeapMb.clamp(kWorkerNodeMinHeapMb, kWorkerNodeMaxHeapMb);
  }
  final total = totalPhysicalMb ?? 0;
  if (total <= 0) return kWorkerNodeFallbackHeapMb;
  // 约 75% 给 Node 堆上限，其余留给系统、看板与 Unity 等宿主进程。
  final budget = (total * 0.75).round();
  return budget.clamp(kWorkerNodeMinHeapMb, kWorkerNodeMaxHeapMb);
}

int? parseKanbanWorkerHeapMb(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed);
}

/// 若已有 `--max-old-space-size` 则保留用户设置，否则补上看板计算出的堆上限。
String applyWorkerNodeHeapLimit(
  String? existingNodeOptions, {
  required int mb,
}) {
  final flag = '--max-old-space-size=$mb';
  final current = existingNodeOptions?.trim() ?? '';
  if (current.isEmpty) return flag;
  if (RegExp(
    r'--max-old-space-size(?:\s*=\s*|\s+)\d+',
    caseSensitive: false,
  ).hasMatch(current)) {
    return current;
  }
  return '$current $flag';
}

int? parseNodeMaxOldSpaceSizeMb(String? nodeOptions) {
  final match = RegExp(
    r'--max-old-space-size(?:\s*=\s*|\s+)(\d+)',
    caseSensitive: false,
  ).firstMatch(nodeOptions ?? '');
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
