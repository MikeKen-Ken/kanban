import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'agent_dispatch_config.dart';

/// Agent 调度本机偏好（不同步）。
class AgentDispatchSettings {
  const AgentDispatchSettings({
    this.engine = AgentDispatchEngine.cursor,
    this.projectId,
    this.repoPath,
    this.model,
    this.effort = AgentDispatchEffort.default_,
    this.maxCards = 1,
    this.autoSubmitVerify = true,
    this.autoBlockOnFail = true,
    this.useProject = false,
    this.useRepo = true,
    this.useModel = false,
    this.useEffort = false,
    this.useMultiCard = false,
    this.workerScriptPath,
    this.repoPathByProject = const {},
  });

  final AgentDispatchEngine engine;
  final String? projectId;
  final String? repoPath;
  final String? model;
  final AgentDispatchEffort effort;
  final int maxCards;
  final bool autoSubmitVerify;
  final bool autoBlockOnFail;

  /// 复选框：是否指定项目 / 仓库 / 模型 / 思考程度 / 多卡。
  final bool useProject;
  final bool useRepo;
  final bool useModel;
  final bool useEffort;
  final bool useMultiCard;

  /// 可选：覆盖 worker 脚本路径（`cli.js`）。
  final String? workerScriptPath;

  /// 各看板项目最近使用的仓库路径。
  final Map<String, String> repoPathByProject;

  AgentDispatchSettings copyWith({
    AgentDispatchEngine? engine,
    Object? projectId = _sentinel,
    Object? repoPath = _sentinel,
    Object? model = _sentinel,
    AgentDispatchEffort? effort,
    int? maxCards,
    bool? autoSubmitVerify,
    bool? autoBlockOnFail,
    bool? useProject,
    bool? useRepo,
    bool? useModel,
    bool? useEffort,
    bool? useMultiCard,
    Object? workerScriptPath = _sentinel,
    Map<String, String>? repoPathByProject,
  }) {
    return AgentDispatchSettings(
      engine: engine ?? this.engine,
      projectId: projectId == _sentinel ? this.projectId : projectId as String?,
      repoPath: repoPath == _sentinel ? this.repoPath : repoPath as String?,
      model: model == _sentinel ? this.model : model as String?,
      effort: effort ?? this.effort,
      maxCards: maxCards ?? this.maxCards,
      autoSubmitVerify: autoSubmitVerify ?? this.autoSubmitVerify,
      autoBlockOnFail: autoBlockOnFail ?? this.autoBlockOnFail,
      useProject: useProject ?? this.useProject,
      useRepo: useRepo ?? this.useRepo,
      useModel: useModel ?? this.useModel,
      useEffort: useEffort ?? this.useEffort,
      useMultiCard: useMultiCard ?? this.useMultiCard,
      workerScriptPath: workerScriptPath == _sentinel
          ? this.workerScriptPath
          : workerScriptPath as String?,
      repoPathByProject: repoPathByProject ?? this.repoPathByProject,
    );
  }

  AgentDispatchRunOptions toRunOptions({String? activeProjectId}) {
    final projectId = useProject ? this.projectId : activeProjectId;
    final repoFromMap = projectId == null
        ? null
        : repoPathByProject[projectId];
    return AgentDispatchRunOptions(
      engine: engine,
      projectId: projectId,
      repoPath: useRepo ? (repoPath ?? repoFromMap) : repoFromMap,
      model: useModel ? model : null,
      effort: useEffort ? effort : AgentDispatchEffort.default_,
      maxCards: useMultiCard ? maxCards.clamp(1, 50) : 1,
      autoSubmitVerify: autoSubmitVerify,
      autoBlockOnFail: autoBlockOnFail,
    );
  }

  Map<String, dynamic> toJson() => {
        'engine': engine.name,
        if (projectId != null) 'projectId': projectId,
        if (repoPath != null) 'repoPath': repoPath,
        if (model != null) 'model': model,
        'effort': effort.wireName,
        'maxCards': maxCards,
        'autoSubmitVerify': autoSubmitVerify,
        'autoBlockOnFail': autoBlockOnFail,
        'useProject': useProject,
        'useRepo': useRepo,
        'useModel': useModel,
        'useEffort': useEffort,
        'useMultiCard': useMultiCard,
        if (workerScriptPath != null) 'workerScriptPath': workerScriptPath,
        if (repoPathByProject.isNotEmpty)
          'repoPathByProject': repoPathByProject,
      };

  factory AgentDispatchSettings.fromJson(Map<String, dynamic> json) {
    final mapRaw = json['repoPathByProject'] as Map<String, dynamic>?;
    return AgentDispatchSettings(
      engine: AgentDispatchEngine.fromName(json['engine'] as String?),
      projectId: json['projectId'] as String?,
      repoPath: json['repoPath'] as String?,
      model: json['model'] as String?,
      effort: AgentDispatchEffort.fromName(json['effort'] as String?),
      maxCards: (json['maxCards'] as num?)?.toInt() ?? 1,
      autoSubmitVerify: json['autoSubmitVerify'] as bool? ?? true,
      autoBlockOnFail: json['autoBlockOnFail'] as bool? ?? true,
      useProject: json['useProject'] as bool? ?? false,
      useRepo: json['useRepo'] as bool? ?? true,
      useModel: json['useModel'] as bool? ?? false,
      useEffort: json['useEffort'] as bool? ?? false,
      useMultiCard: json['useMultiCard'] as bool? ?? false,
      workerScriptPath: json['workerScriptPath'] as String?,
      repoPathByProject: mapRaw == null
          ? const {}
          : mapRaw.map((k, v) => MapEntry(k, v as String)),
    );
  }
}

const Object _sentinel = Object();

extension AgentDispatchSettingsStore on SharedPreferences {
  static const _key = 'agent_dispatch_settings';

  AgentDispatchSettings loadAgentDispatchSettings() {
    final raw = getString(_key);
    if (raw == null) return const AgentDispatchSettings();
    try {
      return AgentDispatchSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AgentDispatchSettings();
    }
  }

  Future<void> saveAgentDispatchSettings(AgentDispatchSettings settings) {
    return setString(_key, jsonEncode(settings.toJson()));
  }
}
