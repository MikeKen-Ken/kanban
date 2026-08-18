import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../mcp/mcp_git_commit.dart';
import 'agent_dispatch_after_queue.dart';
import 'agent_dispatch_config.dart';

/// 单个 AI 平台在工作台里记住的模型与参数。
class AgentDispatchEngineProfile {
  const AgentDispatchEngineProfile({
    this.modelId,
    this.modelParamValues = const {},
  });

  final String? modelId;
  final Map<String, String> modelParamValues;

  Map<String, dynamic> toJson() => {
        if (modelId != null && modelId!.trim().isNotEmpty) 'modelId': modelId,
        if (modelParamValues.isNotEmpty) 'modelParamValues': modelParamValues,
      };

  factory AgentDispatchEngineProfile.fromJson(Map<String, dynamic> json) {
    final raw = json['modelParamValues'] as Map<String, dynamic>?;
    return AgentDispatchEngineProfile(
      modelId: json['modelId'] as String?,
      modelParamValues: raw == null
          ? const {}
          : raw.map((key, value) => MapEntry(key, '$value')),
    );
  }
}

/// Agent 调度本机偏好（不同步）。
class AgentDispatchSettings {
  const AgentDispatchSettings({
    this.engine = AgentDispatchEngine.cursor,
    this.useProject = false,
    this.projectId,
    this.repoPath,
    this.modelId = defaultModelId,
    this.modelParamValues = defaultModelParamValues,
    this.engineProfiles = const {},
    this.ignoreCardParams = false,
    this.allowDirtyWorkspace = false,
    this.enableSandbox = false,
    this.cardLimitMax = true,
    this.cardLimitCount = 1,
    this.afterQueue = const [],
    this.runAfterQueueOnFailure = true,
    this.workerScriptPath,
    this.skillPath,
    this.repoPathByProject = const {},
    this.repoPaths = const [],
    this.gitAuthorName,
    this.gitAuthorEmail,
  });

  /// 新建调度设置的默认模型。
  static const defaultModelId = 'composer-2.5';

  /// 快速模式关闭，思考程度 Medium。
  static const defaultModelParamValues = {
    'fast': 'false',
    'reasoning_effort': 'medium',
    'context': '64k',
  };

  final AgentDispatchEngine engine;
  final bool useProject;
  final String? projectId;
  final String? repoPath;
  final String? modelId;

  /// 当前模型的参数值，参数定义来自 Cursor 模型 catalog。
  final Map<String, String> modelParamValues;

  /// 各平台上次配置；切换下拉框时恢复，不互相覆盖。
  final Map<String, AgentDispatchEngineProfile> engineProfiles;

  /// 为 true 时忽略卡片覆盖。工作台文案为「允许使用卡片参数」，勾选对应本字段为 false。
  final bool ignoreCardParams;

  /// 工作台默认：关闭时脏工作区停止批次。
  final bool allowDirtyWorkspace;

  /// 工作台默认：关闭时 Cursor SDK 不启用沙箱。
  final bool enableSandbox;

  final bool cardLimitMax;
  final int cardLimitCount;

  /// 批次结束后按顺序执行的动作。
  final List<AgentDispatchAfterStep> afterQueue;

  /// 批次因配额、网络等失败时仍执行完成后队列；手动停止不会触发。默认勾选。
  final bool runAfterQueueOnFailure;

  final String? workerScriptPath;
  final String? skillPath;
  final Map<String, String> repoPathByProject;
  final List<String> repoPaths;

  /// 提交 / rebase 推送使用的作者名；空则回退默认。
  final String? gitAuthorName;

  /// 提交 / rebase 推送使用的作者邮箱；空则回退默认。
  final String? gitAuthorEmail;

  AgentDispatchSettings copyWith({
    AgentDispatchEngine? engine,
    bool? useProject,
    Object? projectId = _sentinel,
    Object? repoPath = _sentinel,
    Object? modelId = _sentinel,
    Map<String, String>? modelParamValues,
    Map<String, AgentDispatchEngineProfile>? engineProfiles,
    bool? ignoreCardParams,
    bool? allowDirtyWorkspace,
    bool? enableSandbox,
    bool? cardLimitMax,
    int? cardLimitCount,
    List<AgentDispatchAfterStep>? afterQueue,
    bool? runAfterQueueOnFailure,
    Object? workerScriptPath = _sentinel,
    Object? skillPath = _sentinel,
    Map<String, String>? repoPathByProject,
    List<String>? repoPaths,
    Object? gitAuthorName = _sentinel,
    Object? gitAuthorEmail = _sentinel,
  }) {
    return AgentDispatchSettings(
      engine: engine ?? this.engine,
      useProject: useProject ?? this.useProject,
      projectId: projectId == _sentinel ? this.projectId : projectId as String?,
      repoPath: repoPath == _sentinel ? this.repoPath : repoPath as String?,
      modelId: modelId == _sentinel ? this.modelId : modelId as String?,
      modelParamValues: modelParamValues ?? this.modelParamValues,
      engineProfiles: engineProfiles ?? this.engineProfiles,
      ignoreCardParams: ignoreCardParams ?? this.ignoreCardParams,
      allowDirtyWorkspace: allowDirtyWorkspace ?? this.allowDirtyWorkspace,
      enableSandbox: enableSandbox ?? this.enableSandbox,
      cardLimitMax: cardLimitMax ?? this.cardLimitMax,
      cardLimitCount: cardLimitCount ?? this.cardLimitCount,
      afterQueue: afterQueue ?? this.afterQueue,
      runAfterQueueOnFailure:
          runAfterQueueOnFailure ?? this.runAfterQueueOnFailure,
      workerScriptPath: workerScriptPath == _sentinel
          ? this.workerScriptPath
          : workerScriptPath as String?,
      skillPath: skillPath == _sentinel ? this.skillPath : skillPath as String?,
      repoPathByProject: repoPathByProject ?? this.repoPathByProject,
      repoPaths: repoPaths ?? this.repoPaths,
      gitAuthorName: gitAuthorName == _sentinel
          ? this.gitAuthorName
          : gitAuthorName as String?,
      gitAuthorEmail: gitAuthorEmail == _sentinel
          ? this.gitAuthorEmail
          : gitAuthorEmail as String?,
    );
  }

  /// 解析某项目的代码仓库：优先项目绑定，未绑定时才回退旧的全局路径。
  String? repoPathFor(String? projectId) {
    final mapped =
        projectId == null ? null : repoPathByProject[projectId]?.trim();
    if (mapped != null && mapped.isNotEmpty) return mapped;
    final fallback = repoPath?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  /// 把仓库绑到指定项目，并记入历史；不改写其它项目或全局 [repoPath]。
  AgentDispatchSettings bindRepoToProject(String projectId, String path) {
    final trimmed = path.trim();
    final map = Map<String, String>.from(repoPathByProject);
    if (trimmed.isEmpty) {
      map.remove(projectId);
      return copyWith(repoPathByProject: map);
    }
    map[projectId] = trimmed;
    return copyWith(repoPathByProject: map).rememberRepoPath(trimmed);
  }

  AgentDispatchSettings rememberRepoPath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return this;
    return copyWith(
      repoPaths: [
        normalized,
        ...repoPaths.where((item) => item != normalized),
      ],
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

  /// 把当前平台的模型写回分平台配置，避免切换后丢失。
  AgentDispatchSettings rememberActiveEngineProfile() {
    final profiles =
        Map<String, AgentDispatchEngineProfile>.from(engineProfiles);
    profiles[engine.name] = AgentDispatchEngineProfile(
      modelId: modelId,
      modelParamValues: modelParamValues,
    );
    return copyWith(engineProfiles: profiles);
  }

  /// 切换平台时先记住当前项，再恢复目标平台上次的模型。
  AgentDispatchSettings switchEngine(AgentDispatchEngine next) {
    final saved = rememberActiveEngineProfile();
    if (next == engine) return saved;
    final profile = saved.engineProfiles[next.name];
    return saved.copyWith(
      engine: next,
      modelId: profile?.modelId,
      modelParamValues: profile?.modelParamValues ?? const {},
    );
  }

  Map<String, AgentDispatchEngineProfile> resolvedEngineProfiles() {
    final profiles =
        Map<String, AgentDispatchEngineProfile>.from(engineProfiles);
    profiles[engine.name] = AgentDispatchEngineProfile(
      modelId: modelId,
      modelParamValues: modelParamValues,
    );
    return profiles;
  }

  static List<({String id, String value})> _runParams(
    Map<String, String> values,
  ) {
    return values.entries
        .where((entry) =>
            entry.key.trim().isNotEmpty &&
            entry.value.trim().isNotEmpty &&
            entry.value != 'default')
        .map((entry) => (id: entry.key, value: entry.value))
        .toList();
  }

  AgentDispatchRunOptions toRunOptions({
    required String? Function(String projectId) projectTitleOf,
    Map<AgentDispatchEngine, List<AgentDispatchModelInfo>> catalogs = const {},
  }) {
    final title =
        useProject && projectId != null ? projectTitleOf(projectId!) : null;
    final profiles = resolvedEngineProfiles();
    final defaultProfile = profiles[engine.name];
    final engineDefaults = <String, AgentDispatchEngineRunDefaults>{
      for (final item in AgentDispatchEngine.values)
        item.name: AgentDispatchEngineRunDefaults(
          modelId: profiles[item.name]?.modelId,
          modelParams: _runParams(
            profiles[item.name]?.modelParamValues ?? const {},
          ),
          models: catalogs[item] ?? const [],
        ),
    };
    return AgentDispatchRunOptions(
      engine: engine,
      projectId: useProject ? projectId : null,
      projectTitle: useProject ? title : null,
      repoPath: repoPathFor(useProject ? projectId : null) ?? '',
      modelId: defaultProfile?.modelId,
      modelParams: _runParams(defaultProfile?.modelParamValues ?? const {}),
      engineDefaults: engineDefaults,
      ignoreCardParams: ignoreCardParams,
      allowDirtyWorkspace: allowDirtyWorkspace,
      enableSandbox: enableSandbox,
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
        if (engineProfiles.isNotEmpty)
          'engineProfiles': {
            for (final entry in engineProfiles.entries)
              entry.key: entry.value.toJson(),
          },
        'ignoreCardParams': ignoreCardParams,
        'allowDirtyWorkspace': allowDirtyWorkspace,
        'enableSandbox': enableSandbox,
        'cardLimitMax': cardLimitMax,
        'cardLimitCount': cardLimitCount,
        if (afterQueue.isNotEmpty)
          'afterQueue': afterQueue.map((step) => step.name).toList(),
        'runAfterQueueOnFailure': runAfterQueueOnFailure,
        if (workerScriptPath != null) 'workerScriptPath': workerScriptPath,
        if (skillPath != null) 'skillPath': skillPath,
        if (repoPathByProject.isNotEmpty)
          'repoPathByProject': repoPathByProject,
        if (repoPaths.isNotEmpty) 'repoPaths': repoPaths,
        if (gitAuthorName != null && gitAuthorName!.trim().isNotEmpty)
          'gitAuthorName': gitAuthorName,
        if (gitAuthorEmail != null && gitAuthorEmail!.trim().isNotEmpty)
          'gitAuthorEmail': gitAuthorEmail,
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
    final engine = AgentDispatchEngine.fromName(json['engine'] as String?);
    final modelId = json['modelId'] as String? ?? legacyModel ?? defaultModelId;
    final profilesRaw = json['engineProfiles'] as Map<String, dynamic>?;
    final engineProfiles = <String, AgentDispatchEngineProfile>{
      if (profilesRaw != null)
        for (final entry in profilesRaw.entries)
          if (entry.value is Map)
            entry.key: AgentDispatchEngineProfile.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
    };
    if (engineProfiles[engine.name] == null) {
      engineProfiles[engine.name] = AgentDispatchEngineProfile(
        modelId: modelId,
        modelParamValues: modelParamValues,
      );
    }
    return AgentDispatchSettings(
      engine: engine,
      useProject: json['useProject'] as bool? ?? false,
      projectId: json['projectId'] as String?,
      repoPath: repoPath,
      modelId: modelId,
      modelParamValues: modelParamValues,
      engineProfiles: engineProfiles,
      ignoreCardParams: json['ignoreCardParams'] as bool? ?? false,
      allowDirtyWorkspace: json['allowDirtyWorkspace'] as bool? ?? false,
      enableSandbox: json['enableSandbox'] as bool? ?? false,
      cardLimitMax: json['cardLimitMax'] as bool? ?? true,
      cardLimitCount: (json['cardLimitCount'] as num?)?.toInt() ??
          (json['maxCards'] as num?)?.toInt() ??
          1,
      afterQueue: parseAgentDispatchAfterQueue(json['afterQueue']),
      runAfterQueueOnFailure: json['runAfterQueueOnFailure'] as bool? ?? true,
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
      gitAuthorName: json['gitAuthorName'] as String?,
      gitAuthorEmail: json['gitAuthorEmail'] as String?,
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
    if (raw == null) {
      applyMcpGitAuthorIdentity();
      return const AgentDispatchSettings();
    }
    try {
      final settings = AgentDispatchSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      applyMcpGitAuthorIdentity(
        name: settings.gitAuthorName,
        email: settings.gitAuthorEmail,
      );
      return settings;
    } catch (_) {
      applyMcpGitAuthorIdentity();
      return const AgentDispatchSettings();
    }
  }

  Future<void> saveAgentDispatchSettings(AgentDispatchSettings settings) async {
    await setString(
      _key,
      jsonEncode(settings.toJson()),
    );
    await persistMcpGitAuthorIdentity(
      name: settings.gitAuthorName,
      email: settings.gitAuthorEmail,
      prefs: this,
    );
  }
}
