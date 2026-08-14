import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// 已保存 Cursor API Key 的摘要（不含密钥明文）。
class CursorApiKeySummary {
  const CursorApiKeySummary({
    required this.id,
    required this.label,
    required this.isActive,
  });

  final String id;
  final String label;
  final bool isActive;
}

class _CursorApiKeyMeta {
  const _CursorApiKeyMeta({required this.id, required this.label});

  final String id;
  final String label;

  Map<String, dynamic> toJson() => {'id': id, 'label': label};

  factory _CursorApiKeyMeta.fromJson(Map<String, dynamic> json) {
    return _CursorApiKeyMeta(
      id: json['id'] as String,
      label: json['label'] as String? ?? 'Key',
    );
  }
}

/// Agent 调度凭据，仅保存在本机安全存储中，不进入偏好、备份或同步数据。
class AgentDispatchCredentials {
  const AgentDispatchCredentials({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _metaKey = 'agent_dispatch_cursor_api_keys_meta';
  static const _activeIdKey = 'agent_dispatch_cursor_api_key_active';
  static const _valuePrefix = 'agent_dispatch_cursor_api_key_';

  final FlutterSecureStorage _storage;

  String _valueKey(String id) => '$_valuePrefix$id';

  String _defaultLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 4) return 'Key ····';
    return 'Key ···${trimmed.substring(trimmed.length - 4)}';
  }

  Future<List<_CursorApiKeyMeta>> _readMeta() async {
    final raw = await _storage.read(key: _metaKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_CursorApiKeyMeta.fromJson)
        .toList(growable: false);
  }

  Future<void> _writeMeta(List<_CursorApiKeyMeta> items) async {
    if (items.isEmpty) {
      await _storage.delete(key: _metaKey);
      return;
    }
    await _storage.write(
      key: _metaKey,
      value: jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<String?> _readActiveId() async {
    final active = (await _storage.read(key: _activeIdKey))?.trim();
    if (active != null && active.isNotEmpty) return active;
    final meta = await _readMeta();
    return meta.isEmpty ? null : meta.first.id;
  }

  Future<String?> _readValue(String id) async {
    final value = (await _storage.read(key: _valueKey(id)))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<List<CursorApiKeySummary>> listStoredCursorApiKeys() async {
    final meta = await _readMeta();
    final activeId = await _readActiveId();
    return [
      for (final item in meta)
        CursorApiKeySummary(
          id: item.id,
          label: item.label,
          isActive: item.id == activeId,
        ),
    ];
  }

  Future<String?> readStoredCursorApiKey() async {
    final activeId = await _readActiveId();
    if (activeId == null) return null;
    return _readValue(activeId);
  }

  String? readEnvironmentCursorApiKey() {
    final value = Platform.environment['CURSOR_API_KEY']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> resolveCursorApiKey() async {
    return await readStoredCursorApiKey() ?? readEnvironmentCursorApiKey();
  }

  Future<void> setActiveCursorApiKey(String id) async {
    final meta = await _readMeta();
    if (!meta.any((item) => item.id == id)) {
      throw StateError('Cursor API Key 不存在');
    }
    await _storage.write(key: _activeIdKey, value: id);
  }

  /// 仅更新当前激活 Key 的显示别名；无已保存 Key 时静默跳过。
  Future<void> updateActiveCursorApiKeyLabel(String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    final activeId = await _readActiveId();
    if (activeId == null) return;
    final meta = await _readMeta();
    final index = meta.indexWhere((item) => item.id == activeId);
    if (index < 0 || meta[index].label == trimmed) return;
    final updated = [...meta];
    updated[index] = _CursorApiKeyMeta(id: activeId, label: trimmed);
    await _writeMeta(updated);
  }

  Future<void> saveCursorApiKey(String value, {String? label}) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Cursor API Key 不能为空');
    }
    final id = const Uuid().v4();
    final meta = await _readMeta();
    final nextLabel = label?.trim().isNotEmpty == true
        ? label!.trim()
        : _defaultLabel(normalized);
    await _storage.write(key: _valueKey(id), value: normalized);
    await _writeMeta([...meta, _CursorApiKeyMeta(id: id, label: nextLabel)]);
    await _storage.write(key: _activeIdKey, value: id);
    final stored = await _readValue(id);
    if (stored != normalized) {
      throw StateError('Cursor API Key 写入后无法从系统安全存储读回');
    }
  }

  /// 更新当前激活 Key 的凭据；无已保存 Key 时退化为 [saveCursorApiKey]。
  Future<void> replaceActiveCursorApiKey(String value, {String? label}) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Cursor API Key 不能为空');
    }
    final activeId = await _readActiveId();
    if (activeId == null) {
      await saveCursorApiKey(normalized, label: label);
      return;
    }
    final meta = await _readMeta();
    final index = meta.indexWhere((item) => item.id == activeId);
    if (index < 0) {
      await saveCursorApiKey(normalized, label: label);
      return;
    }
    final nextLabel = label?.trim().isNotEmpty == true
        ? label!.trim()
        : meta[index].label;
    await _storage.write(key: _valueKey(activeId), value: normalized);
    final updated = [...meta];
    updated[index] = _CursorApiKeyMeta(id: activeId, label: nextLabel);
    await _writeMeta(updated);
    final stored = await _readValue(activeId);
    if (stored != normalized) {
      throw StateError('Cursor API Key 写入后无法从系统安全存储读回');
    }
  }

  Future<void> deleteCursorApiKey([String? id]) async {
    final targetId = id ?? await _readActiveId();
    if (targetId == null) return;
    final meta = await _readMeta();
    final remaining =
        meta.where((item) => item.id != targetId).toList(growable: false);
    await _storage.delete(key: _valueKey(targetId));
    if (remaining.isEmpty) {
      await _storage.delete(key: _metaKey);
      await _storage.delete(key: _activeIdKey);
      return;
    }
    await _writeMeta(remaining);
    final activeId = await _readActiveId();
    if (activeId == targetId) {
      await _storage.write(key: _activeIdKey, value: remaining.first.id);
    }
  }
}
