import 'dart:io';

import 'package:flutter/foundation.dart';

import 'mcp_client_config.dart';
import 'mcp_paths.dart';

enum McpClientKind { cursor, codex }

class McpConfigureResult {
  const McpConfigureResult({
    required this.ok,
    required this.message,
    this.path,
  });

  final bool ok;
  final String message;
  final String? path;
}

/// 反向一键配置：把本机 MCP 端点写入 Cursor / Codex 全局配置。
abstract final class McpClientConfigurator {
  static Future<bool> isConfigured(
    McpClientKind kind, {
    required int port,
  }) async {
    if (!McpPaths.isWindowsSupported) return false;
    final path = _pathFor(kind);
    if (path == null) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    final text = await file.readAsString();
    return switch (kind) {
      McpClientKind.cursor =>
        McpClientConfig.isCursorConfigured(text, port: port),
      McpClientKind.codex =>
        McpClientConfig.isCodexConfigured(text, port: port),
    };
  }

  static Future<McpConfigureResult> configure(
    McpClientKind kind, {
    required int port,
  }) async {
    if (!McpPaths.isWindowsSupported) {
      return const McpConfigureResult(
        ok: false,
        message: 'One-click MCP client setup is available on Windows only',
      );
    }

    final path = _pathFor(kind);
    if (path == null) {
      return const McpConfigureResult(
        ok: false,
        message: 'Could not resolve the user configuration path',
      );
    }

    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final existing = await file.exists() ? await file.readAsString() : null;
      final next = switch (kind) {
        McpClientKind.cursor =>
          McpClientConfig.upsertCursorJson(existing, port: port),
        McpClientKind.codex =>
          McpClientConfig.upsertCodexToml(existing, port: port),
      };
      await file.writeAsString(next);
      final label = kind == McpClientKind.cursor ? 'Cursor' : 'Codex';
      return McpConfigureResult(
        ok: true,
        path: path,
        message: '$label configuration saved. Restart $label, then enable MCP.',
      );
    } catch (error) {
      debugPrint('One-click MCP configuration failed: $error');
      return McpConfigureResult(
        ok: false,
        path: path,
        message: 'Could not save configuration: $error',
      );
    }
  }

  static String? _pathFor(McpClientKind kind) => switch (kind) {
        McpClientKind.cursor => McpPaths.cursorMcpJsonPath,
        McpClientKind.codex => McpPaths.codexConfigTomlPath,
      };
}
