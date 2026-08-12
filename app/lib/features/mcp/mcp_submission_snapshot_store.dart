import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 取卡时冻结的本轮提交范围；仅存本机，不参与 WebDAV 同步。
class McpSubmissionSnapshot {
  const McpSubmissionSnapshot({
    required this.projectId,
    required this.cardId,
    required this.workMode,
    required this.suggestedCommitMessage,
    this.incompleteFeedbackIds = const [],
    required this.capturedAt,
  });

  final String projectId;
  final String cardId;
  final String workMode;
  final String suggestedCommitMessage;
  final List<String> incompleteFeedbackIds;
  final int capturedAt;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'cardId': cardId,
        'workMode': workMode,
        'suggestedCommitMessage': suggestedCommitMessage,
        if (incompleteFeedbackIds.isNotEmpty)
          'incompleteFeedbackIds': incompleteFeedbackIds,
        'capturedAt': capturedAt,
      };

  factory McpSubmissionSnapshot.fromJson(Map<String, dynamic> json) {
    final workMode = json['workMode'] as String;
    if (workMode != 'normal' && workMode != 'rework') {
      throw const FormatException('workMode 无效');
    }
    return McpSubmissionSnapshot(
      projectId: json['projectId'] as String,
      cardId: json['cardId'] as String,
      workMode: workMode,
      suggestedCommitMessage: json['suggestedCommitMessage'] as String,
      incompleteFeedbackIds:
          (json['incompleteFeedbackIds'] as List? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      capturedAt: json['capturedAt'] as int? ?? 0,
    );
  }
}

class McpSubmissionSnapshotStore {
  McpSubmissionSnapshotStore({
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'kanban.mcp.submissionSnapshot.v1';

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<McpSubmissionSnapshot?> read({
    required String projectId,
    required String cardId,
  }) async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(_key(projectId, cardId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return McpSubmissionSnapshot.fromJson(json);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> write(McpSubmissionSnapshot snapshot) async {
    final prefs = await _prefsLoader();
    await prefs.setString(
      _key(snapshot.projectId, snapshot.cardId),
      jsonEncode(snapshot.toJson()),
    );
  }

  String _key(String projectId, String cardId) =>
      '$_keyPrefix.${Uri.encodeComponent(projectId)}.${Uri.encodeComponent(cardId)}';
}
