import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_worker_environment.dart';

void main() {
  test('合并 PATH 时去重且先出现的优先', () {
    expect(
      mergePathEntries(
        const [
          r'C:\node',
          r'C:\flutter\bin;C:\Windows',
          r'C:\Windows;C:\Users\me\bin',
        ],
        separator: ';',
      ),
      r'C:\node;C:\flutter\bin;C:\Windows;C:\Users\me\bin',
    );
  });

  test('Windows PATH 去重不区分大小写', () {
    expect(
      mergePathEntries(
        const [r'C:\Flutter\bin', r'c:\flutter\bin;C:\Windows'],
        separator: ';',
      ),
      r'C:\Flutter\bin;C:\Windows',
    );
  });

  test('展开注册表 PATH 中的 %USERPROFILE%', () {
    expect(
      expandWindowsEnvVars(
        r'%USERPROFILE%\dev\flutter\bin;C:\Windows',
        const {'USERPROFILE': r'C:\Users\me'},
      ),
      r'C:\Users\me\dev\flutter\bin;C:\Windows',
    );
  });

  test('解析 reg query 的 REG_EXPAND_SZ 值', () {
    const stdout = '''
HKEY_CURRENT_USER\\Environment
    Path    REG_EXPAND_SZ    %USERPROFILE%\\bin;C:\\flutter\\bin
''';
    expect(
      parseRegQueryValue(stdout, 'Path'),
      r'%USERPROFILE%\bin;C:\flutter\bin',
    );
  });

  test('Worker 环境把用户 PATH 与 FLUTTER_ROOT/bin 补进查找路径', () {
    final built = buildWorkerEnvironment(
      processEnvironment: const {
        'USERPROFILE': r'C:\Users\me',
        'Path': r'C:\Windows',
      },
      nodeExecutable: r'C:\kanban\agent_worker\runtime\node.exe',
      windowsRegistry: const WindowsRegistryEnvironment(
        machinePath: r'C:\Windows\System32',
        userPath: r'%USERPROFILE%\dev\flutter\bin',
        userFlutterRoot: r'%USERPROFILE%\dev\flutter',
      ),
      directoryExists: (path) =>
          path == r'C:\Users\me\dev\flutter\bin',
      pathSeparator: ';',
      totalPhysicalMemoryMb: 32768,
    );

    expect(
      built.environment['Path'],
      r'C:\kanban\agent_worker\runtime;C:\Users\me\dev\flutter\bin;C:\Windows\System32;C:\Windows',
    );
    expect(built.environment['PATH'], built.environment['Path']);
    expect(built.environment['FLUTTER_ROOT'], r'C:\Users\me\dev\flutter');
    expect(built.summary, contains('已合并用户/系统 PATH'));
    expect(built.summary, contains(r'C:\Users\me\dev\flutter\bin'));
    expect(built.summary, contains('Node 堆上限 24576MB'));
    expect(
      built.environment['NODE_OPTIONS'],
      '--max-old-space-size=24576',
    );
  });

  test('会发现 LOCALAPPDATA 下的 Flutter SDK', () {
    final built = buildWorkerEnvironment(
      processEnvironment: const {
        'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
        'Path': r'C:\Windows',
      },
      nodeExecutable: r'C:\node\node.exe',
      directoryExists: (path) =>
          path == r'C:\Users\me\AppData\Local\flutter\bin',
      pathSeparator: ';',
    );

    expect(
      built.environment['Path'],
      r'C:\node;C:\Users\me\AppData\Local\flutter\bin;C:\Windows',
    );
    expect(
      built.environment['FLUTTER_ROOT'],
      r'C:\Users\me\AppData\Local\flutter',
    );
    expect(built.summary, contains(r'C:\Users\me\AppData\Local\flutter\bin'));
  });

  test('进程已有 FLUTTER_ROOT 时优先于注册表', () {
    final built = buildWorkerEnvironment(
      processEnvironment: const {
        'FLUTTER_ROOT': r'D:\sdk\flutter',
        'Path': r'C:\Windows',
      },
      nodeExecutable: r'C:\node\node.exe',
      windowsRegistry: const WindowsRegistryEnvironment(
        userFlutterRoot: r'C:\other\flutter',
      ),
      directoryExists: (path) => path == r'D:\sdk\flutter\bin',
      pathSeparator: ';',
    );

    expect(built.environment['Path']!.startsWith(r'C:\node;D:\sdk\flutter\bin;'), isTrue);
    expect(built.environment['FLUTTER_ROOT'], r'D:\sdk\flutter');
  });

  test('注册表读取失败时沿用进程 PATH', () {
    final built = buildWorkerEnvironment(
      processEnvironment: const {'Path': r'C:\Windows'},
      nodeExecutable: r'C:\node\node.exe',
      pathSeparator: ';',
      totalPhysicalMemoryMb: 32768,
    );

    expect(built.environment['Path'], r'C:\node;C:\Windows');
    expect(built.summary, contains('沿用看板进程 PATH'));
    expect(built.summary, contains('Node 堆上限 24576MB'));
    expect(built.summary, contains('本机物理内存 32768MB'));
    expect(
      built.environment['NODE_OPTIONS'],
      '--max-old-space-size=24576',
    );
  });

  test('已有 NODE_OPTIONS 堆上限时不覆盖', () {
    final built = buildWorkerEnvironment(
      processEnvironment: const {
        'Path': r'C:\Windows',
        'NODE_OPTIONS': '--enable-source-maps --max-old-space-size=8192',
      },
      nodeExecutable: r'C:\node\node.exe',
      pathSeparator: ';',
    );

    expect(
      built.environment['NODE_OPTIONS'],
      '--enable-source-maps --max-old-space-size=8192',
    );
    expect(built.summary, contains('Node 堆上限 8192MB'));
  });

  test('已有 NODE_OPTIONS 但无堆上限时追加计算出的值', () {
    expect(
      applyWorkerNodeHeapLimit('--enable-source-maps', mb: 16384),
      '--enable-source-maps --max-old-space-size=16384',
    );
  });

  test('KANBAN_WORKER_HEAP_MB 可覆盖自动堆上限', () {
    final built = buildWorkerEnvironment(
      processEnvironment: const {
        'Path': r'C:\Windows',
        'KANBAN_WORKER_HEAP_MB': '12288',
      },
      nodeExecutable: r'C:\node\node.exe',
      pathSeparator: ';',
      totalPhysicalMemoryMb: 32768,
    );
    expect(
      built.environment['NODE_OPTIONS'],
      '--max-old-space-size=12288',
    );
    expect(built.summary, contains('用户指定'));
  });

  test('按物理内存选择 Node 堆上限', () {
    expect(chooseWorkerNodeHeapMb(totalPhysicalMb: 8192), 6144);
    expect(chooseWorkerNodeHeapMb(totalPhysicalMb: 16384), 12288);
    expect(chooseWorkerNodeHeapMb(totalPhysicalMb: 32768), 24576);
    expect(chooseWorkerNodeHeapMb(totalPhysicalMb: 65536), 49152);
    expect(chooseWorkerNodeHeapMb(), 8192);
    expect(
      chooseWorkerNodeHeapMb(totalPhysicalMb: 32768, explicitHeapMb: 20000),
      20000,
    );
  });

  test('注入的 reg query 能读出用户 PATH 与 FLUTTER_ROOT', () {
    final registry = readWindowsRegistryEnvironment(
      query: (key, valueName) {
        if (key.contains('HKCU') && valueName == 'Path') {
          return (
            exitCode: 0,
            stdout: '    Path    REG_SZ    C:\\flutter\\bin\n',
          );
        }
        if (key.contains('HKCU') && valueName == 'FLUTTER_ROOT') {
          return (
            exitCode: 0,
            stdout: '    FLUTTER_ROOT    REG_SZ    C:\\flutter\n',
          );
        }
        return (exitCode: 1, stdout: '');
      },
    );
    expect(registry.userPath, r'C:\flutter\bin');
    expect(registry.userFlutterRoot, r'C:\flutter');
    expect(registry.hasPath, isTrue);
  });
}
