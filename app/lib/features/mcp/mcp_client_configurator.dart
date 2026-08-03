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
        message: '仅 Windows 支持一键配置 MCP 客户端',
      );
    }

    final path = _pathFor(kind);
    if (path == null) {
      return const McpConfigureResult(
        ok: false,
        message: '无法解析用户配置路径',
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
        message: '已写入 $label 配置，请重启 $label 后启用 MCP',
      );
    } catch (error) {
      debugPrint('一键配置 MCP 失败：$error');
      return McpConfigureResult(
        ok: false,
        path: path,
        message: '写入失败：$error',
      );
    }
  }

  static String? _pathFor(McpClientKind kind) => switch (kind) {
        McpClientKind.cursor => McpPaths.cursorMcpJsonPath,
        McpClientKind.codex => McpPaths.codexConfigTomlPath,
      };
}
