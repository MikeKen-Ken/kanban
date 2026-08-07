/// 同步阶段（用于进度展示；不扩展 [SyncStatus]）
enum SyncPhase {
  discovering,
  downloading,
  merging,
  uploading,
  attachments,
  finalizing,
}

/// 文件/项目级同步进度
class SyncProgress {
  const SyncProgress({
    required this.phase,
    this.completed = 0,
    this.total,
    this.currentLabel,
    this.skipped = 0,
  });

  final SyncPhase phase;
  final int completed;
  final int? total;
  final String? currentLabel;

  /// 因未变更而跳过的 JSON 文件数（上传/拉取阶段均可能有意义）
  final int skipped;

  static const idle = SyncProgress(phase: SyncPhase.discovering);

  bool get hasTotal => total != null && total! > 0;

  String get phaseLabel => switch (phase) {
        SyncPhase.discovering => '准备同步',
        SyncPhase.downloading => '拉取远端',
        SyncPhase.merging => '合并',
        SyncPhase.uploading => '上传',
        SyncPhase.attachments => '同步附件',
        SyncPhase.finalizing => '收尾',
      };

  /// 顶栏短文案，例如「同步中 3/12」
  String get shortLabel {
    if (hasTotal) {
      return '同步中 $completed/$total';
    }
    return '同步中…';
  }

  SyncProgress copyWith({
    SyncPhase? phase,
    int? completed,
    Object? total = _sentinel,
    Object? currentLabel = _sentinel,
    int? skipped,
  }) {
    return SyncProgress(
      phase: phase ?? this.phase,
      completed: completed ?? this.completed,
      total: identical(total, _sentinel) ? this.total : total as int?,
      currentLabel: identical(currentLabel, _sentinel)
          ? this.currentLabel
          : currentLabel as String?,
      skipped: skipped ?? this.skipped,
    );
  }

  static const _sentinel = Object();
}
