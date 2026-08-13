enum AgentDispatchLogLevel { info, success, warning, error }

class AgentDispatchLogEntry {
  const AgentDispatchLogEntry(this.message,
      {this.level = AgentDispatchLogLevel.info});

  final String message;
  final AgentDispatchLogLevel level;

  String format(DateTime time) {
    final stamp = time.toLocal().toIso8601String().substring(11, 19);
    return '[$stamp] [${level.label}] $message';
  }

  static AgentDispatchLogLevel levelOf(String line) {
    for (final level in AgentDispatchLogLevel.values) {
      if (line.contains('[${level.label}]')) return level;
    }
    return AgentDispatchLogLevel.info;
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
