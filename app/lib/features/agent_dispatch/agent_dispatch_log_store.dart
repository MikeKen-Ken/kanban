import 'package:shared_preferences/shared_preferences.dart';

/// Agent 工具对话记录，仅保存在本机，避免日志无限增长。
extension AgentDispatchLogStore on SharedPreferences {
  static const _key = 'agent_dispatch_tool_log';
  static const _maxChars = 100000;

  String loadAgentDispatchLog() => getString(_key) ?? '';

  Future<void> saveAgentDispatchLog(String value) {
    final normalized = value.length <= _maxChars
        ? value
        : '…（较早记录已省略）\n${value.substring(value.length - _maxChars)}';
    return setString(_key, normalized);
  }

  Future<void> clearAgentDispatchLog() => remove(_key);
}
