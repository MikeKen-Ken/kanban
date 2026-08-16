import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

enum DispatchPendingStatus {
  declared,
  validated,
  committing,
  committed,
  finalized,
  failed,
}

class DispatchVerificationCommand {
  const DispatchVerificationCommand({
    required this.executable,
    required this.args,
    this.cwd = '.',
    this.timeoutMs,
    this.expectedExitCode = 0,
  });

  final String executable;
  final List<String> args;
  final String cwd;
  final int? timeoutMs;
  final int expectedExitCode;

  String get commandSummary {
    final parts = [executable, ...args];
    return parts.map(_quoteCommandPart).join(' ');
  }

  bool get hasRepoRelativeCwd {
    final normalized = cwd.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      return false;
    }
    var depth = 0;
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (depth == 0) return false;
        depth--;
      } else {
        depth++;
      }
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'executable': executable,
        'args': args,
        'cwd': cwd,
        if (timeoutMs != null) 'timeoutMs': timeoutMs,
        'expectedExitCode': expectedExitCode,
      };

  factory DispatchVerificationCommand.fromJson(Map<String, dynamic> json) {
    final executable = json['executable'] as String?;
    if (executable != null) {
      return DispatchVerificationCommand(
        executable: executable,
        args: (json['args'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        cwd: json['cwd'] as String? ?? '.',
        timeoutMs: (json['timeoutMs'] as num?)?.toInt(),
        expectedExitCode: (json['expectedExitCode'] as num?)?.toInt() ?? 0,
      );
    }

    // 旧 pending 仅保存 shell 字符串；读取时迁移为显式 shell 可执行文件。
    final command = json['command'] as String;
    return DispatchVerificationCommand(
      executable: Platform.isWindows ? 'powershell.exe' : '/bin/sh',
      args: Platform.isWindows
          ? ['-NoProfile', '-NonInteractive', '-Command', command]
          : ['-c', command],
      expectedExitCode: (json['expectedExitCode'] as num?)?.toInt() ?? 0,
    );
  }
}

class DispatchValidationResult {
  const DispatchValidationResult({
    required this.commandSummary,
    required this.executable,
    required this.args,
    required this.cwd,
    required this.exitCode,
    required this.durationMs,
    required this.timedOut,
    this.output,
  });

  final String commandSummary;
  final String executable;
  final List<String> args;
  final String cwd;
  final int exitCode;
  final int durationMs;
  final bool timedOut;
  final String? output;

  Map<String, dynamic> toJson() => {
        'commandSummary': commandSummary,
        'executable': executable,
        'args': args,
        'cwd': cwd,
        'exitCode': exitCode,
        'durationMs': durationMs,
        'timedOut': timedOut,
        if (output != null) 'output': output,
      };

  factory DispatchValidationResult.fromJson(Map<String, dynamic> json) {
    final legacyCommand = json['command'] as String?;
    return DispatchValidationResult(
      commandSummary:
          json['commandSummary'] as String? ?? legacyCommand ?? '旧验证命令',
      executable: json['executable'] as String? ?? '',
      args: (json['args'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      cwd: json['cwd'] as String? ?? '.',
      exitCode: (json['exitCode'] as num).toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      timedOut: json['timedOut'] as bool? ?? false,
      output: json['output'] as String?,
    );
  }
}

class DispatchPendingRecord {
  const DispatchPendingRecord({
    required this.sessionId,
    required this.projectId,
    required this.cardId,
    required this.status,
    required this.completedChecklistIds,
    required this.completedFeedbackIds,
    required this.verificationCommands,
    required this.updatedAt,
    this.repoPath,
    this.baselineCommitRef,
    this.manualVerificationReason,
    this.validationResults = const [],
    this.commitRef,
    this.error,
    this.workerToken,
  });

  final String sessionId;

  /// 仅用于当前进程内的过渡，不写入 JSON。
  final String? workerToken;
  final String projectId;
  final String cardId;
  final DispatchPendingStatus status;
  final List<String> completedChecklistIds;
  final List<String> completedFeedbackIds;
  final List<DispatchVerificationCommand> verificationCommands;
  final String? repoPath;
  final String? baselineCommitRef;
  final String? manualVerificationReason;
  final List<DispatchValidationResult> validationResults;
  final String? commitRef;
  final String? error;
  final int updatedAt;

  DispatchPendingRecord copyWith({
    String? workerToken,
    DispatchPendingStatus? status,
    List<DispatchValidationResult>? validationResults,
    String? commitRef,
    String? error,
    bool clearError = false,
    int? updatedAt,
  }) =>
      DispatchPendingRecord(
        sessionId: sessionId,
        workerToken: workerToken ?? this.workerToken,
        projectId: projectId,
        cardId: cardId,
        status: status ?? this.status,
        completedChecklistIds: completedChecklistIds,
        completedFeedbackIds: completedFeedbackIds,
        verificationCommands: verificationCommands,
        repoPath: repoPath,
        baselineCommitRef: baselineCommitRef,
        manualVerificationReason: manualVerificationReason,
        validationResults: validationResults ?? this.validationResults,
        commitRef: commitRef ?? this.commitRef,
        error: clearError ? null : (error ?? this.error),
        updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'projectId': projectId,
        'cardId': cardId,
        'status': status.name,
        'completedChecklistIds': completedChecklistIds,
        'completedFeedbackIds': completedFeedbackIds,
        'verificationCommands':
            verificationCommands.map((item) => item.toJson()).toList(),
        if (repoPath != null) 'repoPath': repoPath,
        if (baselineCommitRef != null) 'baselineCommitRef': baselineCommitRef,
        if (manualVerificationReason != null)
          'manualVerificationReason': manualVerificationReason,
        'validationResults':
            validationResults.map((item) => item.toJson()).toList(),
        if (commitRef != null) 'commitRef': commitRef,
        if (error != null) 'error': error,
        'updatedAt': updatedAt,
      };

  factory DispatchPendingRecord.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String;
    return DispatchPendingRecord(
      sessionId: json['sessionId'] as String,
      projectId: json['projectId'] as String,
      cardId: json['cardId'] as String,
      status: DispatchPendingStatus.values.byName(statusName),
      completedChecklistIds:
          (json['completedChecklistIds'] as List? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      completedFeedbackIds: (json['completedFeedbackIds'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      verificationCommands: (json['verificationCommands'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => DispatchVerificationCommand.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
      repoPath: json['repoPath'] as String?,
      baselineCommitRef: json['baselineCommitRef'] as String?,
      manualVerificationReason: json['manualVerificationReason'] as String?,
      validationResults: (json['validationResults'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => DispatchValidationResult.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
      commitRef: json['commitRef'] as String?,
      error: json['error'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class DispatchPendingStore {
  DispatchPendingStore({
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const _prefix = 'kanban.mcp.dispatchPending.v1';
  static const _maxTerminalRecords = 100;
  final Future<SharedPreferences> Function() _prefsLoader;

  Future<DispatchPendingRecord?> read(String sessionId) async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(_key(sessionId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final record = DispatchPendingRecord.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (decoded.containsKey('workerToken')) {
        await prefs.setString(_key(sessionId), jsonEncode(record.toJson()));
      }
      return record;
    } on Object {
      return null;
    }
  }

  Future<void> write(DispatchPendingRecord record) async {
    final prefs = await _prefsLoader();
    await prefs.setString(_key(record.sessionId), jsonEncode(record.toJson()));
    await _prune(prefs);
  }

  Future<List<DispatchPendingRecord>> list() async {
    final prefs = await _prefsLoader();
    final records = <DispatchPendingRecord>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('$_prefix.')) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final record =
            DispatchPendingRecord.fromJson(Map<String, dynamic>.from(decoded));
        records.add(record);
        if (decoded.containsKey('workerToken')) {
          await prefs.setString(key, jsonEncode(record.toJson()));
        }
      } on Object {
        // 忽略单条损坏的本机 pending，保留其它可恢复事务。
      }
    }
    records.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    await _prune(prefs, records: records);
    return records;
  }

  Future<void> delete(String sessionId) async {
    final prefs = await _prefsLoader();
    await prefs.remove(_key(sessionId));
  }

  String _key(String sessionId) => '$_prefix.${Uri.encodeComponent(sessionId)}';

  Future<void> _prune(
    SharedPreferences prefs, {
    List<DispatchPendingRecord>? records,
  }) async {
    final all = records ?? await _readAll(prefs);
    final terminal = all
        .where((record) =>
            record.status == DispatchPendingStatus.finalized ||
            record.status == DispatchPendingStatus.failed)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final record in terminal.skip(_maxTerminalRecords)) {
      await prefs.remove(_key(record.sessionId));
    }
  }

  Future<List<DispatchPendingRecord>> _readAll(
    SharedPreferences prefs,
  ) async {
    final records = <DispatchPendingRecord>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('$_prefix.')) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          records.add(
            DispatchPendingRecord.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } on Object {
        // 损坏记录不会阻止其它事务清理。
      }
    }
    return records;
  }
}

String _quoteCommandPart(String value) {
  if (value.isEmpty) return '""';
  if (!RegExp(r'\s|["]').hasMatch(value)) return value;
  return jsonEncode(value);
}
