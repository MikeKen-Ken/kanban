/// 非 IO 平台：无用户配置路径。
abstract final class McpPaths {
  static String? get cursorMcpJsonPath => null;
  static String? get codexConfigTomlPath => null;
  static bool get isWindowsSupported => false;
}
