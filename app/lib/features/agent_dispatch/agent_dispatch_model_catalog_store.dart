import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'agent_dispatch_config.dart';

extension AgentDispatchModelCatalogStore on SharedPreferences {
  static const _key = 'agent_dispatch_model_catalog';

  List<AgentDispatchModelInfo> loadAgentDispatchModelCatalog({
    AgentDispatchEngine engine = AgentDispatchEngine.cursor,
  }) {
    final raw = getString('${_key}_${engine.name}') ??
        (engine == AgentDispatchEngine.cursor ? getString(_key) : null);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(AgentDispatchModelInfo.fromJson)
          .where((model) => model.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAgentDispatchModelCatalog(
    List<AgentDispatchModelInfo> models, {
    AgentDispatchEngine engine = AgentDispatchEngine.cursor,
  }) {
    return setString(
      '${_key}_${engine.name}',
      jsonEncode(models.map((model) => model.toJson()).toList()),
    );
  }
}
