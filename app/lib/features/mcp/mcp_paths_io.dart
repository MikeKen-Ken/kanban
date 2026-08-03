import 'dart:io';

import 'package:path/path.dart' as p;

/// 基于环境变量的 Cursor / Codex 配置路径（不硬编码用户名）。
abstract final class McpPaths {
  static String get _userProfile {
    final fromEnv = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return Directory.current.path;
  }

  static String get cursorMcpJsonPath =>
      p.join(_userProfile, '.cursor', 'mcp.json');

  static String get codexConfigTomlPath =>
      p.join(_userProfile, '.codex', 'config.toml');

  static bool get isWindowsSupported => Platform.isWindows;
}
