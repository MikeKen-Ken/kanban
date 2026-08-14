import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'workspace_snapshot.dart';

/// 上次成功合并后的工作区基线，供三路合并判断「相对 base 谁改了」
class SyncBaseStore {
  SyncBaseStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'kanban_sync_base_workspace';
  static const _workspaceShaKey = 'kanban_live_workspace_sha256';
  static const _wallpapersShaKey = 'kanban_live_wallpapers_sha256';

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
    await _prefs.remove(_workspaceShaKey);
    await _prefs.remove(_wallpapersShaKey);
  }

  String? loadLiveWorkspaceSha256() => _prefs.getString(_workspaceShaKey);

  Future<void> saveLiveWorkspaceSha256(String sha256) =>
      _prefs.setString(_workspaceShaKey, sha256);

  String? loadLiveWallpapersSha256() => _prefs.getString(_wallpapersShaKey);

  Future<void> saveLiveWallpapersSha256(String sha256) =>
      _prefs.setString(_wallpapersShaKey, sha256);
}
