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
        SyncPhase.discovering => 'Preparing sync',
        SyncPhase.downloading => 'Downloading remote data',
        SyncPhase.merging => 'Merging',
        SyncPhase.uploading => 'Uploading',
        SyncPhase.attachments => 'Syncing attachments',
        SyncPhase.finalizing => 'Finalizing',
      };

  /// 顶栏短文案，例如「同步中 3/12」
  String get shortLabel {
    if (hasTotal) {
      return 'Syncing $completed/$total';
    }
    return 'Syncing…';
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
