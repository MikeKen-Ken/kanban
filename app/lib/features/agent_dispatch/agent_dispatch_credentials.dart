import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Agent 调度凭据，仅保存在本机安全存储中，不进入偏好、备份或同步数据。
class AgentDispatchCredentials {
  const AgentDispatchCredentials({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _cursorApiKey = 'agent_dispatch_cursor_api_key';

  final FlutterSecureStorage _storage;

  Future<String?> readStoredCursorApiKey() async {
    final value = (await _storage.read(key: _cursorApiKey))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? readEnvironmentCursorApiKey() {
    final value = Platform.environment['CURSOR_API_KEY']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> resolveCursorApiKey() async {
    return await readStoredCursorApiKey() ?? readEnvironmentCursorApiKey();
  }

  Future<void> saveCursorApiKey(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Cursor API Key 不能为空');
    }
    await _storage.write(key: _cursorApiKey, value: normalized);
    final stored = await readStoredCursorApiKey();
    if (stored != normalized) {
      throw StateError('Cursor API Key 写入后无法从系统安全存储读回');
    }
  }

  Future<void> deleteCursorApiKey() => _storage.delete(key: _cursorApiKey);
}
