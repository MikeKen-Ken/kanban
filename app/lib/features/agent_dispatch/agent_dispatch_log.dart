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
    final levelMatch =
        RegExp(r'^\[(success|warning|error|err)\]\s*').firstMatch(line);
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

  static String messageOf(String line) {
    final match = RegExp(
      r'^\[\d{2}:\d{2}:\d{2}\] \[[^\]]+\](?: \[[^\]]+\])? (.*)$',
    ).firstMatch(line);
    return (match?.group(1) ?? line).trim();
  }

  /// Converts system-generated log text for display without changing the raw
  /// Chinese protocol markers used by progress parsing and persisted history.
  static String displayLine(String line) {
    var displayed = line
        .replaceAll('[系统]', '[System]')
        .replaceAll('[信息]', '[Info]')
        .replaceAll('[成功]', '[Success]')
        .replaceAll('[警告]', '[Warning]')
        .replaceAll('[失败]', '[Error]')
        .replaceAll('[命令]', '[Command]');
    const replacements = <String, String>{
      'Worker 批次启动：': 'Worker batch started: ',
      'Worker 已连接完整看板 MCP，正在恢复未完成收尾':
          'Worker connected to Kanban MCP; recovering unfinished finalization',
      '当前无更多卡片': 'No more cards',
      'claim 时队列已为空': 'The queue was empty during claim',
      'Worker 正在实施当前卡片': 'Worker is implementing the current card',
      'Worker 正在提交当前卡片': 'Worker is submitting the current card',
      'Worker 正在提交并送交验证': 'Worker is submitting and sending for verification',
      'Worker 已关闭完整看板 MCP 连接': 'Worker closed the Kanban MCP connection',
      '验证已由 Agent 会话完成，Worker 不再复跑测试':
          'Verification completed in the Agent session; Worker will not rerun tests',
      'Worker 批次完成：': 'Worker batch complete: ',
      '当前卡片：': 'Current card: ',
      '当前任务：': 'Current task: ',
      '引擎：': 'Engine: ',
      '由调度总览启动': 'Started from Dispatch overview',
      '已停止运行': 'Run stopped',
      '本地会话已创建，开始执行…': 'Local session created; starting execution…',
      '收尾工具已成功': 'Finalization tool succeeded',
      '思考完成（': 'Thinking completed (',
      ' 秒）': 's)',
      '已处理 ': 'Processed ',
      ' 张': ' card(s)',
      '已恢复 pending 会话': 'Recovered pending session',
      '第 ': 'Attempt ',
      ' 次 Agent 会话失败': ' Agent session failed',
      '自动重试': 'automatic retry',
      '完成后队列：开始': 'After-completion queue started',
      '完成后队列：已完成': 'After-completion queue completed',
    };
    for (final entry in replacements.entries) {
      displayed = displayed.replaceAll(entry.key, entry.value);
    }
    return displayed;
  }

  /// 没有具体内容的进度行不展示，避免刷屏。
  static bool isLowValue(String line) {
    final message = messageOf(line);
    if (message == '思考中…' || message == '思考中') return true;
    if (RegExp(r'^│\s*$').hasMatch(message)) return true;
    if (RegExp(r'^工具：\S+$').hasMatch(message)) return true;
    if (RegExp(r'^工具结果：\S+$').hasMatch(message)) return true;
    if (RegExp(r'^命令：（空）$').hasMatch(message)) return true;
    if (RegExp(r'^步骤：\S+$').hasMatch(message)) return true;
    return false;
  }

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
        AgentDispatchLogLevel.info => 'Info',
        AgentDispatchLogLevel.success => 'Success',
        AgentDispatchLogLevel.warning => 'Warning',
        AgentDispatchLogLevel.error => 'Error',
      };
}

extension AgentDispatchLogSourceLabel on AgentDispatchLogSource {
  String get label => switch (this) {
        AgentDispatchLogSource.system => 'System',
        AgentDispatchLogSource.worker => 'Worker',
        AgentDispatchLogSource.ai => 'AI',
        AgentDispatchLogSource.mcp => 'MCP',
        AgentDispatchLogSource.shell => 'Command',
      };
}

/// 运行日志中会话指标（token、耗时等）的高亮分段，供界面重点着色。
class AgentDispatchLogHighlight {
  AgentDispatchLogHighlight._();

  static final RegExp _emphasisPattern = RegExp(
    r'本会话 token|'
    r'\b(?:input|output|cacheRead|cacheWrite|total)=\d+|'
    r'\b(?:steps|tools|elapsedMs)=\d+|'
    r'\b(?:repeatedToolCalls|repeatedReads)=\d+|'
    r'会话诊断|用户 Rule 注入|SDK 扫描|'
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
        result
            .add((text: line.substring(cursor, match.start), emphasis: false));
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

/// 按 Worker 单卡轮次把日志切成「第几个任务」。
class AgentDispatchLogTask {
  const AgentDispatchLogTask({
    required this.ordinal,
    required this.roundIndex,
    required this.roundTotal,
    required this.title,
    required this.start,
    required this.end,
  });

  /// 日志中出现的第几个任务，从 1 起。
  final int ordinal;
  final int roundIndex;
  final int roundTotal;
  final String title;
  final int start;
  final int end;

  String get label {
    final head = 'Task $ordinal';
    if (title.isNotEmpty) return '$head · $title';
    if (roundTotal > 0) return '$head · $roundIndex/$roundTotal';
    return '$head · $roundIndex';
  }
}

class AgentDispatchLogTasks {
  AgentDispatchLogTasks._();

  static final _roundPattern = RegExp(r'Worker 单卡轮次 (\d+)(?:/(\d+))?');
  static final _titlePattern = RegExp(r'^当前卡片：(.+)$');

  static List<AgentDispatchLogTask> parse(List<String> lines) {
    final tasks = <AgentDispatchLogTask>[];
    var ordinal = 0;
    for (var i = 0; i < lines.length; i++) {
      final message = AgentDispatchLogEntry.messageOf(lines[i]);
      final round = _roundPattern.firstMatch(message);
      if (round == null) {
        if (tasks.isNotEmpty && tasks.last.title.isEmpty) {
          final title = _titlePattern.firstMatch(message);
          if (title != null) {
            final last = tasks.removeLast();
            tasks.add(
              AgentDispatchLogTask(
                ordinal: last.ordinal,
                roundIndex: last.roundIndex,
                roundTotal: last.roundTotal,
                title: title.group(1)!.trim(),
                start: last.start,
                end: last.end,
              ),
            );
          }
        }
        continue;
      }
      if (tasks.isNotEmpty) {
        final last = tasks.removeLast();
        tasks.add(
          AgentDispatchLogTask(
            ordinal: last.ordinal,
            roundIndex: last.roundIndex,
            roundTotal: last.roundTotal,
            title: last.title,
            start: last.start,
            end: i,
          ),
        );
      }
      ordinal += 1;
      tasks.add(
        AgentDispatchLogTask(
          ordinal: ordinal,
          roundIndex: int.parse(round.group(1)!),
          roundTotal: int.parse(round.group(2) ?? '0'),
          title: '',
          start: i,
          end: lines.length,
        ),
      );
    }
    return tasks;
  }

  /// [ordinal] 为空表示全部任务。
  static String slice(String text, int? ordinal) {
    if (ordinal == null) return text;
    final lines = text.split('\n');
    final task = parse(lines).where((item) => item.ordinal == ordinal);
    if (task.isEmpty) return '';
    final selected = task.first;
    return lines.sublist(selected.start, selected.end).join('\n');
  }

  static int? ordinalOfLine(List<AgentDispatchLogTask> tasks, int lineIndex) {
    for (final task in tasks) {
      if (lineIndex >= task.start && lineIndex < task.end) return task.ordinal;
    }
    return null;
  }
}
