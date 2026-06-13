import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/kanban_models.dart';

/// WebDAV 连接配置（密码仅存本地 SharedPreferences）
class WebDavConfig {
  const WebDavConfig({
    required this.enabled,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remotePath,
    required this.autoSync,
    required this.pollIntervalSeconds,
  });

  final bool enabled;
  final String serverUrl;
  final String username;
  final String password;
  final String remotePath;
  final bool autoSync;
  final int pollIntervalSeconds;

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  WebDavConfig copyWith({
    bool? enabled,
    String? serverUrl,
    String? username,
    String? password,
    String? remotePath,
    bool? autoSync,
    int? pollIntervalSeconds,
  }) {
    return WebDavConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
      autoSync: autoSync ?? this.autoSync,
      pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'remotePath': remotePath,
        'autoSync': autoSync,
        'pollIntervalSeconds': pollIntervalSeconds,
      };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) {
    return WebDavConfig(
      enabled: json['enabled'] as bool? ?? false,
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '/KanbanApp/board.json',
      autoSync: json['autoSync'] as bool? ?? true,
      pollIntervalSeconds: json['pollIntervalSeconds'] as int? ?? 30,
    );
  }

  static const empty = WebDavConfig(
    enabled: false,
    serverUrl: '',
    username: '',
    password: '',
    remotePath: '/KanbanApp/board.json',
    autoSync: true,
    pollIntervalSeconds: 30,
  );
}

class BoardRepository {
  BoardRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _boardKey = 'kanban_board';
  static const _boardIdKey = 'kanban_board_id';
  static const _webdavKey = 'webdav_config';

  Future<KanbanBoard> loadBoard() async {
    final raw = _prefs.getString(_boardKey);
    if (raw == null) {
      final id = _prefs.getString(_boardIdKey) ?? const Uuid().v4();
      await _prefs.setString(_boardIdKey, id);
      final board = KanbanBoard.empty(id: id);
      await saveBoard(board);
      return board;
    }
    return KanbanBoard.fromJsonString(raw);
  }

  Future<void> saveBoard(KanbanBoard board) async {
    await _prefs.setString(_boardKey, board.toJsonString());
  }

  Future<WebDavConfig> loadWebDavConfig() async {
    final raw = _prefs.getString(_webdavKey);
    if (raw == null) return WebDavConfig.empty;
    return WebDavConfig.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    await _prefs.setString(_webdavKey, jsonEncode(config.toJson()));
  }
}
