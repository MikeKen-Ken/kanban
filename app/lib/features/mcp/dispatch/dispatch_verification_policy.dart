import 'dispatch_pending_store.dart';

/// 单卡收尾只接受与本卡改动相关的定向验证，拒绝全仓库分析/全量测试/构建。
String? dispatchVerificationPolicyError(DispatchVerificationCommand command) {
  final tool = _toolName(command.executable);
  if (tool != 'flutter' && tool != 'dart') return null;

  final args = [
    for (final arg in command.args)
      if (arg.trim().isNotEmpty) arg.trim(),
  ];
  if (args.isEmpty) return null;

  final subcommand = args.first;
  final rest = args.skip(1).toList(growable: false);
  switch (subcommand) {
    case 'analyze':
      if (_hasFileTarget(rest)) return null;
      return 'verificationCommands 禁止全仓库 $tool analyze；请改为针对本卡改动的定向测试';
    case 'test':
      if (_hasFileTarget(rest)) return null;
      return 'verificationCommands 禁止全量 $tool test；请改为具体测试文件';
    case 'build':
    case 'install':
    case 'run':
      return 'verificationCommands 禁止构建、安装或启动应用；请改为定向测试';
    default:
      return null;
  }
}

String _toolName(String executable) {
  final normalized = executable.trim().replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final base =
      (slash >= 0 ? normalized.substring(slash + 1) : normalized).toLowerCase();
  return base.replaceAll(RegExp(r'\.(exe|bat|cmd)$'), '');
}

bool _hasFileTarget(List<String> args) {
  return args.any((arg) {
    if (arg.startsWith('-')) return false;
    return arg.contains('/') ||
        arg.contains('\\') ||
        arg.endsWith('.dart') ||
        arg.endsWith('.yaml');
  });
}
