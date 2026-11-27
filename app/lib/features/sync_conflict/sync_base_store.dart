import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../trash/trash_models.dart';
import 'workspace_snapshot.dart';

/// 上次成功合并后的工作区基线，供三路合并判断「相对 base 谁改了」
class SyncBaseStore {
  SyncBaseStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'kanban_sync_base_workspace';
  static const _workspaceShaKey = 'kanban_live_workspace_sha256';
  static const _wallpapersShaKey = 'kanban_live_wallpapers_sha256';
  static const _remoteScopeKey = 'kanban_sync_base_remote_scope';
  static const _legacyCleanedScopeKey = 'kanban_legacy_tree_cleaned_scope';
  static const _labelTrashShaKey = 'kanban_sync_base_label_trash_sha256';

  static String buildRemoteScope({
    required String serverUrl,
    required String remotePath,
  }) {
    final normalizedUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$normalizedUrl|$remotePath';
  }

  static String hashLabelTrash(List<TrashItem> items) {
    final encoded = jsonEncode(items.map((item) => item.toJson()).toList());
    return sha256.convert(utf8.encode(encoded)).toString();
  }

  /// 确保当前 SyncBase 属于 [scope]；若之前绑定了其它远端则自动清空基线。
  Future<bool> ensureRemoteScope(String scope) async {
    final existing = _prefs.getString(_remoteScopeKey);
    if (existing != null && existing.isNotEmpty && existing != scope) {
      await clear();
      await _prefs.setString(_remoteScopeKey, scope);
      return true;
    }
    if (existing == null || existing.isEmpty) {
      await _prefs.setString(_remoteScopeKey, scope);
    }
    return false;
  }

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

  Future<void> save(
    ProjectWorkspaceSnapshot snapshot, {
    String? remoteScope,
    List<TrashItem>? labelTrash,
  }) async {
    await _prefs.setString(_key, jsonEncode(snapshot.toJson()));
    if (remoteScope != null && remoteScope.isNotEmpty) {
      await _prefs.setString(_remoteScopeKey, remoteScope);
    }
    if (labelTrash != null) {
      await saveLabelTrashSha256(labelTrash);
    }
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_workspaceShaKey);
    await _prefs.remove(_wallpapersShaKey);
    await _prefs.remove(_remoteScopeKey);
    await _prefs.remove(_legacyCleanedScopeKey);
    await _prefs.remove(_labelTrashShaKey);
  }

  String? loadLiveWorkspaceSha256() => _prefs.getString(_workspaceShaKey);

  Future<void> saveLiveWorkspaceSha256(String sha256) =>
      _prefs.setString(_workspaceShaKey, sha256);

  String? loadLiveWallpapersSha256() => _prefs.getString(_wallpapersShaKey);

  Future<void> saveLiveWallpapersSha256(String sha256) =>
      _prefs.setString(_wallpapersShaKey, sha256);

  String? loadLabelTrashSha256() => _prefs.getString(_labelTrashShaKey);

  Future<void> saveLabelTrashSha256(List<TrashItem> items) =>
      _prefs.setString(_labelTrashShaKey, hashLabelTrash(items));

  bool isLegacyTreeCleaned(String scope) =>
      _prefs.getString(_legacyCleanedScopeKey) == scope;

  Future<void> markLegacyTreeCleaned(String scope) =>
      _prefs.setString(_legacyCleanedScopeKey, scope);
}
