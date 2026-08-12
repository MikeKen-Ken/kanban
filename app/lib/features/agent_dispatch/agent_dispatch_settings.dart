import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_dispatch_config.dart';

/// Agent 调度本机偏好（不同步）。
class AgentDispatchSettings {
  const AgentDispatchSettings({
    this.engine = AgentDispatchEngine.cursor,
    this.useProject = false,
    this.projectId,
    this.repoPath,
    this.modelId,
    this.effortParamId,
    this.effortParamValue,
    this.cardLimitMax = false,
    this.cardLimitCount = 1,
    this.workerScriptPath,
    this.skillPath,
    this.repoPathByProject = const {},
    this.repoPaths = const [],
  });

  final AgentDispatchEngine engine;
  final bool useProject;
  final String? projectId;
  final String? repoPath;
  final String? modelId;

  /// 思考/速度类参数（来自模型 catalog）。
  final String? effortParamId;
  final String? effortParamValue;

  final bool cardLimitMax;
  final int cardLimitCount;

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
    Object? effortParamId = _sentinel,
    Object? effortParamValue = _sentinel,
    bool? cardLimitMax,
    int? cardLimitCount,
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
      effortParamId: effortParamId == _sentinel
          ? this.effortParamId
          : effortParamId as String?,
      effortParamValue: effortParamValue == _sentinel
          ? this.effortParamValue
          : effortParamValue as String?,
      cardLimitMax: cardLimitMax ?? this.cardLimitMax,
      cardLimitCount: cardLimitCount ?? this.cardLimitCount,
      workerScriptPath: workerScriptPath == _sentinel
          ? this.workerScriptPath
          : workerScriptPath as String?,
      skillPath: skillPath == _sentinel ? this.skillPath : skillPath as String?,
      repoPathByProject: repoPathByProject ?? this.repoPathByProject,
      repoPaths: repoPaths ?? this.repoPaths,
    );
  }

  AgentDispatchRunOptions toRunOptions({
    required String? Function(String projectId) projectTitleOf,
  }) {
    final title =
        useProject && projectId != null ? projectTitleOf(projectId!) : null;
    final params = <({String id, String value})>[];
    final pid = effortParamId?.trim();
    final pval = effortParamValue?.trim();
    if (pid != null &&
        pid.isNotEmpty &&
        pval != null &&
        pval.isNotEmpty &&
        pval != 'default') {
      params.add((id: pid, value: pval));
    }
    return AgentDispatchRunOptions(
      engine: engine,
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
        if (effortParamId != null) 'effortParamId': effortParamId,
        if (effortParamValue != null) 'effortParamValue': effortParamValue,
        'cardLimitMax': cardLimitMax,
        'cardLimitCount': cardLimitCount,
        if (workerScriptPath != null) 'workerScriptPath': workerScriptPath,
        if (skillPath != null) 'skillPath': skillPath,
        if (repoPathByProject.isNotEmpty)
          'repoPathByProject': repoPathByProject,
        if (repoPaths.isNotEmpty) 'repoPaths': repoPaths,
      };

  factory AgentDispatchSettings.fromJson(Map<String, dynamic> json) {
    final mapRaw = json['repoPathByProject'] as Map<String, dynamic>?;
    final pathsRaw = json['repoPaths'] as List<dynamic>?;
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
    return AgentDispatchSettings(
      engine: AgentDispatchEngine.fromName(json['engine'] as String?),
      useProject: json['useProject'] as bool? ?? false,
      projectId: json['projectId'] as String?,
      repoPath: repoPath,
      modelId: json['modelId'] as String? ?? legacyModel,
      effortParamId: json['effortParamId'] as String?,
      effortParamValue:
          json['effortParamValue'] as String? ?? (json['effort'] as String?),
      cardLimitMax: json['cardLimitMax'] as bool? ??
          (json['useMultiCard'] != true && json['maxCards'] == null
              ? false
              : false),
      cardLimitCount: (json['cardLimitCount'] as num?)?.toInt() ??
          (json['maxCards'] as num?)?.toInt() ??
          1,
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
    return setString(_key, jsonEncode(settings.toJson()));
  }
}
