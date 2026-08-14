import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_dispatch_after_queue.dart';
import 'agent_dispatch_config.dart';

/// Agent 调度本机偏好（不同步）。
class AgentDispatchSettings {
  const AgentDispatchSettings({
    this.engine = AgentDispatchEngine.cursor,
    this.useProject = false,
    this.projectId,
    this.repoPath,
    this.modelId = defaultModelId,
    this.modelParamValues = defaultModelParamValues,
    this.cardLimitMax = true,
    this.cardLimitCount = 1,
    this.afterQueue = const [],
    this.workerScriptPath,
    this.skillPath,
    this.repoPathByProject = const {},
    this.repoPaths = const [],
  });

  /// 新建调度设置的默认模型。
  static const defaultModelId = 'composer-2.5';

  /// 快速模式关闭，思考程度 Medium。
  static const defaultModelParamValues = {
    'fast': 'false',
    'reasoning_effort': 'medium',
  };

  final AgentDispatchEngine engine;
  final bool useProject;
  final String? projectId;
  final String? repoPath;
  final String? modelId;

  /// 当前模型的参数值，参数定义来自 Cursor 模型 catalog。
  final Map<String, String> modelParamValues;

  final bool cardLimitMax;
  final int cardLimitCount;

  /// 批次成功结束后按顺序执行的动作。
  final List<AgentDispatchAfterStep> afterQueue;

  final String? workerScriptPath;
  final String? skillPath;
  final Map<String, String> repoPathByProject;
  final List<String> repoPaths;

  AgentDispatchSettings copyWith({
    AgentDispatchEngine? engine,
    bool? useProject,
    Object? projectId = _sentinel,
    Object? repoPath = _sentinel,
    Object? modelId = _sentinel,
    Map<String, String>? modelParamValues,
    bool? cardLimitMax,
    int? cardLimitCount,
    List<AgentDispatchAfterStep>? afterQueue,
    Object? workerScriptPath = _sentinel,
    Object? skillPath = _sentinel,
    Map<String, String>? repoPathByProject,
    List<String>? repoPaths,
  }) {
    return AgentDispatchSettings(
      engine: engine ?? this.engine,
      useProject: useProject ?? this.useProject,
      projectId: projectId == _sentinel ? this.projectId : projectId as String?,
      repoPath: repoPath == _sentinel ? this.repoPath : repoPath as String?,
      modelId: modelId == _sentinel ? this.modelId : modelId as String?,
      modelParamValues: modelParamValues ?? this.modelParamValues,
      cardLimitMax: cardLimitMax ?? this.cardLimitMax,
      cardLimitCount: cardLimitCount ?? this.cardLimitCount,
      afterQueue: afterQueue ?? this.afterQueue,
      workerScriptPath: workerScriptPath == _sentinel
          ? this.workerScriptPath
          : workerScriptPath as String?,
      skillPath: skillPath == _sentinel ? this.skillPath : skillPath as String?,
      repoPathByProject: repoPathByProject ?? this.repoPathByProject,
      repoPaths: repoPaths ?? this.repoPaths,
    );
  }

  /// 从本机历史中忘记一个仓库，并移除引用它的项目默认值。
  AgentDispatchSettings forgetRepoPath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return this;
    return copyWith(
      repoPath: repoPath?.trim() == normalized ? null : repoPath,
      repoPaths: repoPaths.where((item) => item != normalized).toList(),
      repoPathByProject: Map<String, String>.from(repoPathByProject)
        ..removeWhere((_, value) => value.trim() == normalized),
    );
  }

  AgentDispatchRunOptions toRunOptions({
    required String? Function(String projectId) projectTitleOf,
  }) {
    final title =
        useProject && projectId != null ? projectTitleOf(projectId!) : null;
    final params = modelParamValues.entries
        .where((entry) =>
            entry.key.trim().isNotEmpty &&
            entry.value.trim().isNotEmpty &&
            entry.value != 'default')
        .map((entry) => (id: entry.key, value: entry.value))
        .toList();
    return AgentDispatchRunOptions(
      engine: engine,
      projectId: useProject ? projectId : null,
      projectTitle: useProject ? title : null,
      repoPath: repoPath?.trim() ?? '',
      modelId: modelId,
      modelParams: params,
      cardLimit: cardLimitMax
          ? AgentDispatchCardLimit.max
          : AgentDispatchCardLimit.count(cardLimitCount),
    );
  }

  Map<String, dynamic> toJson() => {
        'engine': engine.name,
        'useProject': useProject,
        if (projectId != null) 'projectId': projectId,
        if (repoPath != null) 'repoPath': repoPath,
        if (modelId != null) 'modelId': modelId,
        if (modelParamValues.isNotEmpty) 'modelParamValues': modelParamValues,
        'cardLimitMax': cardLimitMax,
        'cardLimitCount': cardLimitCount,
        if (afterQueue.isNotEmpty)
          'afterQueue': afterQueue.map((step) => step.name).toList(),
        if (workerScriptPath != null) 'workerScriptPath': workerScriptPath,
        if (skillPath != null) 'skillPath': skillPath,
        if (repoPathByProject.isNotEmpty)
          'repoPathByProject': repoPathByProject,
        if (repoPaths.isNotEmpty) 'repoPaths': repoPaths,
      };

  factory AgentDispatchSettings.fromJson(Map<String, dynamic> json) {
    final mapRaw = json['repoPathByProject'] as Map<String, dynamic>?;
    final pathsRaw = json['repoPaths'] as List<dynamic>?;
    final modelParamsRaw = json['modelParamValues'] as Map<String, dynamic>?;
    final repoPath = json['repoPath'] as String?;
    final migratedPaths = <String>{
      if (repoPath?.trim().isNotEmpty == true) repoPath!.trim(),
      ...?mapRaw?.values
          .whereType<String>()
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty),
    };
    // 兼容旧字段
    final legacyModel = json['model'] as String?;
    final legacyParamId = json['effortParamId'] as String?;
    final legacyParamValue =
        json['effortParamValue'] as String? ?? json['effort'] as String?;
    var modelParamValues = modelParamsRaw == null
        ? <String, String>{
            if (legacyParamId != null && legacyParamValue != null)
              legacyParamId: legacyParamValue,
          }
        : modelParamsRaw.map((key, value) => MapEntry(key, '$value'));
    if (modelParamsRaw == null &&
        legacyParamId == null &&
        legacyParamValue == null) {
      modelParamValues = Map<String, String>.from(defaultModelParamValues);
    } else if (modelParamValues.length == 1 &&
        modelParamValues['fast'] == 'true') {
      modelParamValues = Map<String, String>.from(defaultModelParamValues);
    }
    return AgentDispatchSettings(
      engine: AgentDispatchEngine.fromName(json['engine'] as String?),
      useProject: json['useProject'] as bool? ?? false,
      projectId: json['projectId'] as String?,
      repoPath: repoPath,
      modelId: json['modelId'] as String? ?? legacyModel ?? defaultModelId,
      modelParamValues: modelParamValues,
      // 始终默认勾选「全部」；仅保留上次填写的张数。
      cardLimitMax: true,
      cardLimitCount: (json['cardLimitCount'] as num?)?.toInt() ??
          (json['maxCards'] as num?)?.toInt() ??
          1,
      afterQueue: parseAgentDispatchAfterQueue(json['afterQueue']),
      workerScriptPath: json['workerScriptPath'] as String?,
      skillPath: json['skillPath'] as String?,
      repoPathByProject: mapRaw == null
          ? const {}
          : mapRaw.map((k, v) => MapEntry(k, v as String)),
      repoPaths: pathsRaw == null
          ? migratedPaths.toList()
          : pathsRaw
              .whereType<String>()
              .map((path) => path.trim())
              .where((path) => path.isNotEmpty)
              .toSet()
              .toList(),
    );
  }

  /// 默认 Skill 优先使用当前引擎目录，缺失时回退到另一客户端目录。
  static String defaultSkillPath(AgentDispatchEngine engine) {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final preferred =
        engine == AgentDispatchEngine.codex ? '.codex' : '.cursor';
    final fallback = engine == AgentDispatchEngine.codex ? '.cursor' : '.codex';
    final candidates = [
      p.join(home, preferred, 'skills', 'kanban-complete-tasks', 'SKILL.md'),
      p.join(home, fallback, 'skills', 'kanban-complete-tasks', 'SKILL.md'),
    ];
    return candidates.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => candidates.first,
    );
  }

  String resolveSkillPath() {
    final custom = skillPath?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return defaultSkillPath(engine);
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
    return setString(
      _key,
      jsonEncode(settings.copyWith(cardLimitMax: true).toJson()),
    );
  }
}
