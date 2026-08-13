import 'package:shared_preferences/shared_preferences.dart';

/// Agent 工具对话记录，仅保存在本机。
///
/// 记录必须保留原文：调度失败时，服务端往往会返回多行诊断信息，截断会让
/// 用户无法判断失败原因。凭据仍不得写入此记录，见 ADR-005。
extension AgentDispatchLogStore on SharedPreferences {
  static const _key = 'agent_dispatch_tool_log';

  String loadAgentDispatchLog() => getString(_key) ?? '';

  Future<void> saveAgentDispatchLog(String value) => setString(_key, value);

  Future<void> clearAgentDispatchLog() => remove(_key);
}
