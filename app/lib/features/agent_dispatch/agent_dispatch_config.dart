/// Agent 执行引擎。
enum AgentDispatchEngine {
  cursor,
  codex;

  String get label => switch (this) {
        AgentDispatchEngine.cursor => 'Cursor SDK',
        AgentDispatchEngine.codex => 'Codex exec',
      };

  static AgentDispatchEngine fromName(String? name) {
    return AgentDispatchEngine.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AgentDispatchEngine.cursor,
    );
  }
}

/// 思考 / 速度档位（写入各引擎可识别的参数）。
enum AgentDispatchEffort {
  /// 不传额外参数，用引擎默认。
  default_,
  fast,
  low,
  medium,
  high;

  String get label => switch (this) {
        AgentDispatchEffort.default_ => '默认',
        AgentDispatchEffort.fast => '快速',
        AgentDispatchEffort.low => '低',
        AgentDispatchEffort.medium => '中',
        AgentDispatchEffort.high => '高',
      };

  static AgentDispatchEffort fromName(String? name) {
    if (name == 'default') return AgentDispatchEffort.default_;
    return AgentDispatchEffort.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AgentDispatchEffort.default_,
    );
  }

  String get wireName =>
      this == AgentDispatchEffort.default_ ? 'default' : name;
}

/// 一次调度运行的选项（由面板复选框组装）。
class AgentDispatchRunOptions {
  const AgentDispatchRunOptions({
    required this.engine,
    this.projectId,
    this.repoPath,
    this.model,
    this.effort = AgentDispatchEffort.default_,
    this.maxCards = 1,
    this.autoSubmitVerify = true,
    this.autoBlockOnFail = true,
  });

  final AgentDispatchEngine engine;

  /// 为空则用当前活动项目。
  final String? projectId;

  /// 本机代码仓库路径（local cwd）。
  final String? repoPath;

  /// 为空则用引擎默认模型。
  final String? model;

  final AgentDispatchEffort effort;

  /// 连续取卡并执行的最大张数。
  final int maxCards;

  final bool autoSubmitVerify;
  final bool autoBlockOnFail;
}
