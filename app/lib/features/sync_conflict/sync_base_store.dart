import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'workspace_snapshot.dart';

/// 上次成功合并后的工作区基线，供三路合并判断「相对 base 谁改了」
class SyncBaseStore {
  SyncBaseStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'kanban_sync_base_workspace';

  Future<ProjectWorkspaceSnapshot?> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ProjectWorkspaceSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ProjectWorkspaceSnapshot snapshot) async {
    await _prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
