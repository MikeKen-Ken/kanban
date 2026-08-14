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

/// 卡片数量：固定张数或全部（Max）。
sealed class AgentDispatchCardLimit {
  const AgentDispatchCardLimit();

  static const AgentDispatchCardLimit max = AgentDispatchCardLimitMax();

  factory AgentDispatchCardLimit.count(int n) =>
      AgentDispatchCardLimitCount(n.clamp(1, 999));

  String get label => switch (this) {
        AgentDispatchCardLimitMax() => 'Max（全部）',
        AgentDispatchCardLimitCount(:final count) => '$count',
      };
}

final class AgentDispatchCardLimitMax extends AgentDispatchCardLimit {
  const AgentDispatchCardLimitMax();
}

final class AgentDispatchCardLimitCount extends AgentDispatchCardLimit {
  const AgentDispatchCardLimitCount(this.count);
  final int count;
}

/// 某一平台在工作台里保存的默认模型，供卡片未覆盖时回退。
class AgentDispatchEngineRunDefaults {
  const AgentDispatchEngineRunDefaults({
    this.modelId,
    this.modelParams = const [],
    this.models = const [],
  });

  final String? modelId;
  final List<({String id, String value})> modelParams;
  final List<AgentDispatchModelInfo> models;

  Map<String, dynamic> toJobJson() => {
        if (modelId != null && modelId!.trim().isNotEmpty)
          'model': modelId!.trim(),
        if (modelParams.isNotEmpty)
          'modelParams': [
            for (final item in modelParams) {'id': item.id, 'value': item.value},
          ],
        if (models.isNotEmpty)
          'models': [
            for (final model in models)
              {
                'id': model.id,
                'parameters': [
                  for (final parameter in model.parameters)
                    {'id': parameter.id, 'values': parameter.values},
                ],
              },
          ],
      };
}

/// 一次运行选项。
class AgentDispatchRunOptions {
  const AgentDispatchRunOptions({
    required this.engine,
    required this.repoPath,
    required this.cardLimit,
    this.projectId,
    this.projectTitle,
    this.modelId,
    this.modelParams = const [],
    this.engineDefaults = const {},
  });

  final AgentDispatchEngine engine;

  /// Worker 调用 MCP 时使用的项目 id；为空则使用看板当前项目。
  final String? projectId;

  /// 仅用于调度日志与面板展示；不写入 Skill 调用正文。
  final String? projectTitle;

  /// Agent 工作目录（必填）。
  final String repoPath;

  final String? modelId;

  /// 来自 Cursor.models.list 的 params，如 fast / reasoning_effort。
  final List<({String id, String value})> modelParams;

  /// 各平台工作台默认；卡片指定其它平台时回退到对应项，而不是当前平台。
  final Map<String, AgentDispatchEngineRunDefaults> engineDefaults;

  final AgentDispatchCardLimit cardLimit;

  Map<String, dynamic> engineDefaultsJobJson() => {
        for (final entry in engineDefaults.entries)
          entry.key: entry.value.toJobJson(),
      };
}

/// 模型目录项（worker --list-models）。
class AgentDispatchModelInfo {
  const AgentDispatchModelInfo({
    required this.id,
    this.displayName,
    this.description,
    this.parameters = const [],
    this.variants = const [],
  });

  final String id;
  final String? displayName;
  final String? description;
  final List<AgentDispatchModelParameter> parameters;
  final List<AgentDispatchModelVariant> variants;

  AgentDispatchModelVariant? get defaultVariant {
    for (final variant in variants) {
      if (variant.isDefault) return variant;
    }
    return null;
  }

  /// 下拉展示用名称：只显示官方名，不附加 id 括号。
  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return id;
  }

  factory AgentDispatchModelInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['parameters'] as List<dynamic>? ?? const [];
    return AgentDispatchModelInfo(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String?,
      description: json['description'] as String?,
      parameters: raw
          .whereType<Map<String, dynamic>>()
          .map(AgentDispatchModelParameter.fromJson)
          .where((p) => p.id.isNotEmpty)
          .toList(),
      variants: (json['variants'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AgentDispatchModelVariant.fromJson)
          .where((variant) => variant.displayName.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (displayName != null) 'displayName': displayName,
        if (description != null) 'description': description,
        'parameters':
            parameters.map((parameter) => parameter.toJson()).toList(),
        'variants': variants.map((variant) => variant.toJson()).toList(),
      };
}

String? resolveAgentDispatchModelId(
  List<AgentDispatchModelInfo> models,
  String? currentId, {
  String preferredId = 'composer-2.5',
}) {
  if (models.any((model) => model.id == currentId)) return currentId;
  if (models.any((model) => model.id == preferredId)) return preferredId;
  return models.isEmpty ? null : models.first.id;
}

class AgentDispatchModelParameter {
  const AgentDispatchModelParameter({
    required this.id,
    this.displayName,
    this.options = const [],
  });

  final String id;
  final String? displayName;
  final List<AgentDispatchModelParameterOption> options;

  List<String> get values => options.map((option) => option.value).toList();

  factory AgentDispatchModelParameter.fromJson(Map<String, dynamic> json) {
    final valuesRaw = json['values'] as List<dynamic>? ??
        json['enum'] as List<dynamic>? ??
        const [];
    return AgentDispatchModelParameter(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String?,
      options: valuesRaw
          .map(AgentDispatchModelParameterOption.fromJson)
          .whereType<AgentDispatchModelParameterOption>()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (displayName != null) 'displayName': displayName,
        'values': options.map((option) => option.toJson()).toList(),
      };
}

class AgentDispatchModelParameterOption {
  const AgentDispatchModelParameterOption({
    required this.value,
    this.displayName,
  });

  final String value;
  final String? displayName;

  static AgentDispatchModelParameterOption? fromJson(dynamic raw) {
    final value = raw is Map ? raw['value'] : raw;
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty) return null;
    return AgentDispatchModelParameterOption(
      value: text,
      displayName: raw is Map ? raw['displayName'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        if (displayName != null) 'displayName': displayName,
      };
}

class AgentDispatchModelVariant {
  const AgentDispatchModelVariant({
    required this.displayName,
    this.description,
    this.isDefault = false,
    this.params = const {},
  });

  final String displayName;
  final String? description;
  final bool isDefault;
  final Map<String, String> params;

  factory AgentDispatchModelVariant.fromJson(Map<String, dynamic> json) {
    final params = <String, String>{};
    for (final raw in json['params'] as List<dynamic>? ?? const []) {
      if (raw is! Map) continue;
      final id = raw['id'];
      final value = raw['value'];
      if (id != null && value != null) params['$id'] = '$value';
    }
    return AgentDispatchModelVariant(
      displayName: json['displayName'] as String? ?? '',
      description: json['description'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      params: params,
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        if (description != null) 'description': description,
        if (isDefault) 'isDefault': true,
        'params': [
          for (final entry in params.entries)
            {'id': entry.key, 'value': entry.value},
        ],
      };
}
