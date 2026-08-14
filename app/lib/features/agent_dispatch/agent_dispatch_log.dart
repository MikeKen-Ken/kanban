enum AgentDispatchLogLevel { info, success, warning, error }

/// Agent 工作台日志来源，用于区分系统、Worker、AI、MCP 与命令输出。
enum AgentDispatchLogSource {
  system,
  worker,
  ai,
  mcp,
  shell,
}

class AgentDispatchLogEntry {
  const AgentDispatchLogEntry(
    this.message, {
    this.level = AgentDispatchLogLevel.info,
    this.source = AgentDispatchLogSource.system,
  });

  final String message;
  final AgentDispatchLogLevel level;
  final AgentDispatchLogSource source;

  String format(DateTime time) {
    final stamp = time.toLocal().toIso8601String().substring(11, 19);
    return '[$stamp] [${source.label}] [${level.label}] $message';
  }

  /// 解析 Worker stdout 一行：先级别前缀，再来源前缀，默认来源为 Worker。
  static AgentDispatchLogEntry parseWorkerLine(String raw) {
    var line = raw.trimLeft();
    var level = AgentDispatchLogLevel.info;
    final levelMatch = RegExp(r'^\[(success|warning|error|err)\]\s*').firstMatch(line);
    if (levelMatch != null) {
      level = switch (levelMatch.group(1)) {
        'success' => AgentDispatchLogLevel.success,
        'warning' => AgentDispatchLogLevel.warning,
        'error' => AgentDispatchLogLevel.error,
        'err' => AgentDispatchLogLevel.warning,
        _ => AgentDispatchLogLevel.info,
      };
      line = line.substring(levelMatch.end);
    }

    var source = AgentDispatchLogSource.worker;
    final sourceMatch =
        RegExp(r'^\[(worker|ai|mcp|shell)\]\s*', caseSensitive: false)
            .firstMatch(line);
    if (sourceMatch != null) {
      source = AgentDispatchLogSource.values.byName(sourceMatch.group(1)!);
      line = line.substring(sourceMatch.end);
    }

    return AgentDispatchLogEntry(line, level: level, source: source);
  }

  static AgentDispatchLogLevel levelOf(String line) =>
      _parseFormattedLine(line)?.level ?? AgentDispatchLogLevel.info;

  static AgentDispatchLogSource sourceOf(String line) =>
      _parseFormattedLine(line)?.source ?? _inferLegacySource(line);

  static ({AgentDispatchLogLevel level, AgentDispatchLogSource source})?
      _parseFormattedLine(String line) {
    final match = RegExp(
      r'^\[\d{2}:\d{2}:\d{2}\] \[([^\]]+)\](?: \[([^\]]+)\])? (.*)$',
    ).firstMatch(line);
    if (match == null) return null;

    final tag1 = match.group(1)!;
    final tag2 = match.group(2);
    final message = match.group(3) ?? '';

    if (tag2 != null) {
      final source = _sourceFromLabel(tag1);
      final level = _levelFromLabel(tag2);
      if (source != null && level != null) {
        return (level: level, source: source);
      }
    }

    final legacyLevel = _levelFromLabel(tag1);
    if (legacyLevel != null) {
      return (
        level: legacyLevel,
        source: _inferLegacySource(message),
      );
    }

    final legacySource = _sourceFromLabel(tag1);
    if (legacySource != null) {
      return (level: AgentDispatchLogLevel.info, source: legacySource);
    }

    return null;
  }

  static AgentDispatchLogSource _inferLegacySource(String message) {
    if (message.startsWith('助手：') ||
        message.startsWith('思考：') ||
        message.startsWith('思考中')) {
      return AgentDispatchLogSource.ai;
    }
    if (message.startsWith('工具：')) return AgentDispatchLogSource.mcp;
    if (message.startsWith('命令：')) return AgentDispatchLogSource.shell;
    if (message.startsWith('Worker ') || message.contains('Worker ')) {
      return AgentDispatchLogSource.worker;
    }
    return AgentDispatchLogSource.system;
  }

  static AgentDispatchLogLevel? _levelFromLabel(String label) {
    for (final level in AgentDispatchLogLevel.values) {
      if (label == level.label) return level;
    }
    return null;
  }

  static AgentDispatchLogSource? _sourceFromLabel(String label) {
    for (final source in AgentDispatchLogSource.values) {
      if (label == source.label) return source;
    }
    return null;
  }
}

extension AgentDispatchLogLevelLabel on AgentDispatchLogLevel {
  String get label => switch (this) {
        AgentDispatchLogLevel.info => '信息',
        AgentDispatchLogLevel.success => '成功',
        AgentDispatchLogLevel.warning => '警告',
        AgentDispatchLogLevel.error => '失败',
      };
}

extension AgentDispatchLogSourceLabel on AgentDispatchLogSource {
  String get label => switch (this) {
        AgentDispatchLogSource.system => '系统',
        AgentDispatchLogSource.worker => 'Worker',
        AgentDispatchLogSource.ai => 'AI',
        AgentDispatchLogSource.mcp => 'MCP',
        AgentDispatchLogSource.shell => '命令',
      };
}

/// 运行日志中会话指标（token、耗时等）的高亮分段，供界面重点着色。
class AgentDispatchLogHighlight {
  AgentDispatchLogHighlight._();

  static final RegExp _emphasisPattern = RegExp(
    r'本会话 token|'
    r'\b(?:input|output|total)=\d+|'
    r'\b(?:steps|tools|elapsedMs)=\d+|'
    r'批次 id：\S+|'
    r'Cursor run id=\S+|'
    r'已处理 \d+ 张|'
    r'耗时 \d+ 秒',
  );

  /// 将一行日志拆成普通片段与需重点着色的片段。
  static List<({String text, bool emphasis})> segments(String line) {
    final matches = _emphasisPattern.allMatches(line).toList();
    if (matches.isEmpty) {
      return [(text: line, emphasis: false)];
    }

    final result = <({String text, bool emphasis})>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        result.add((text: line.substring(cursor, match.start), emphasis: false));
      }
      result.add((text: match.group(0)!, emphasis: true));
      cursor = match.end;
    }
    if (cursor < line.length) {
      result.add((text: line.substring(cursor), emphasis: false));
    }
    return result;
  }
}
