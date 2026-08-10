import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class McpRunContext {
  const McpRunContext({
    required this.projectId,
    required this.cardId,
    required this.runId,
    this.lastSubagentId,
    this.baseCommit,
    this.lastCommit,
    this.reviewRound = 0,
    this.handoffSummary,
    this.resumeStatus = 'not_attempted',
    required this.updatedAt,
  });

  final String projectId;
  final String cardId;
  final String runId;
  final String? lastSubagentId;
  final String? baseCommit;
  final String? lastCommit;
  final int reviewRound;
  final String? handoffSummary;
  final String resumeStatus;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'cardId': cardId,
        'runId': runId,
        if (lastSubagentId != null) 'lastSubagentId': lastSubagentId,
        if (baseCommit != null) 'baseCommit': baseCommit,
        if (lastCommit != null) 'lastCommit': lastCommit,
        'reviewRound': reviewRound,
        if (handoffSummary != null) 'handoffSummary': handoffSummary,
        'resumeStatus': resumeStatus,
        'updatedAt': updatedAt,
      };

  factory McpRunContext.fromJson(Map<String, dynamic> json) {
    return McpRunContext(
      projectId: json['projectId'] as String,
      cardId: json['cardId'] as String,
      runId: json['runId'] as String,
      lastSubagentId: json['lastSubagentId'] as String?,
      baseCommit: json['baseCommit'] as String?,
      lastCommit: json['lastCommit'] as String?,
      reviewRound: json['reviewRound'] as int? ?? 0,
      handoffSummary: json['handoffSummary'] as String?,
      resumeStatus: json['resumeStatus'] as String? ?? 'not_attempted',
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}

/// MCP 的本机运行上下文；仅存 SharedPreferences，不参与 WebDAV 同步。
class McpRunContextStore {
  McpRunContextStore({
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'kanban.mcp.runContext.v1';

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<McpRunContext?> read({
    required String projectId,
    required String cardId,
  }) async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(_key(projectId, cardId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return McpRunContext.fromJson(json);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> write(McpRunContext context) async {
    final prefs = await _prefsLoader();
    await prefs.setString(
      _key(context.projectId, context.cardId),
      jsonEncode(context.toJson()),
    );
  }

  Future<void> delete({
    required String projectId,
    required String cardId,
  }) async {
    final prefs = await _prefsLoader();
    await prefs.remove(_key(projectId, cardId));
  }

  String _key(String projectId, String cardId) =>
      '$_keyPrefix.${Uri.encodeComponent(projectId)}.${Uri.encodeComponent(cardId)}';
}
