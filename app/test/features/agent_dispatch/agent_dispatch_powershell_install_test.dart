import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_powershell_install.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_powershell_msi_install.dart';
import 'package:path/path.dart' as p;

void main() {
  test('已有 pwsh 时不调用 winget', () async {
    const pwsh = r'C:\Program Files\PowerShell\7\pwsh.exe';
    var wingetCalls = 0;
    final result = await ensureWindowsPowerShell7(
      environment: const {'ProgramFiles': r'C:\Program Files'},
      separator: ';',
      ctx: p.Context(style: p.Style.windows),
      fileExists: (path) => path == pwsh,
      winget: (_) {
        wingetCalls++;
        return (exitCode: 0, stdout: '', stderr: '');
      },
    );

    expect(wingetCalls, 0);
    expect(result.ok, isTrue);
    expect(result.executable, pwsh);
  });

  test('缺少 pwsh 时先 install 再 upgrade', () async {
    const pwsh = r'D:\Fake\Program Files\PowerShell\7\pwsh.exe';
    const winget = r'D:\Fake\Microsoft\WindowsApps\winget.exe';
    final calls = <String>[];
    var resolveCount = 0;
    final result = await ensureWindowsPowerShell7(
      environment: const {
        'ProgramFiles': r'D:\Fake\Program Files',
        'LOCALAPPDATA': r'D:\Fake',
      },
      separator: ';',
      ctx: p.Context(style: p.Style.windows),
      fileExists: (path) {
        if (path == winget) return true;
        if (path == pwsh) {
          resolveCount++;
          return resolveCount >= 3;
        }
        return false;
      },
      winget: (arguments) {
        calls.add(arguments.first);
        return (exitCode: 0, stdout: 'ok', stderr: '');
      },
      msiInstaller: ({required environment, required ctx}) async =>
          const PowerShellMsiInstallResult(ok: false),
    );

    expect(calls, ['install', 'upgrade']);
    expect(result.ok, isTrue);
    expect(result.installAttempted, isTrue);
    expect(result.installMethod, 'winget');
  });

  test('无 winget 时回退 MSI 安装', () async {
    const pwsh = r'D:\Fake\Program Files\PowerShell\7\pwsh.exe';
    var wingetCalls = 0;
    var msiCalls = 0;
    var msiDone = false;
    final result = await ensureWindowsPowerShell7(
      environment: const {
        'ProgramFiles': r'D:\Fake\Program Files',
        'TEMP': r'C:\Temp',
      },
      separator: ';',
      ctx: p.Context(style: p.Style.windows),
      fileExists: (path) => path == pwsh && msiDone,
      winget: (_) {
        wingetCalls++;
        return (exitCode: 0, stdout: '', stderr: '');
      },
      msiInstaller: ({required environment, required ctx}) async {
        msiCalls++;
        msiDone = true;
        return const PowerShellMsiInstallResult(ok: true, log: 'msi ok');
      },
    );

    expect(wingetCalls, 0);
    expect(msiCalls, 1);
    expect(result.ok, isTrue);
    expect(result.installMethod, 'msi');
    expect(result.summaryFragment, contains('MSI'));
  });

  test('winget 与 MSI 都失败时返回明确错误', () async {
    final result = await ensureWindowsPowerShell7(
      environment: const {
        'ProgramFiles': r'D:\Fake\Program Files',
        'TEMP': r'C:\Temp',
      },
      separator: ';',
      ctx: p.Context(style: p.Style.windows),
      fileExists: (_) => false,
      winget: (_) => (exitCode: 1, stdout: '', stderr: 'failed'),
      msiInstaller: ({required environment, required ctx}) async =>
          const PowerShellMsiInstallResult(
        ok: false,
        error: 'msi failed',
      ),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('未安装 winget'));
    expect(result.error, contains('GitHub MSI'));
  });

  test('resolveWingetExecutable 能识别 WindowsApps 路径', () {
    const winget = r'C:\Users\me\AppData\Local\Microsoft\WindowsApps\winget.exe';
    expect(
      resolveWingetExecutable(
        environment: const {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
        separator: ';',
        ctx: p.Context(style: p.Style.windows),
        fileExists: (path) => path == winget,
      ),
      winget,
    );
  });

  test('winget 已安装退出码仍视为可继续解析', () {
    expect(wingetExitLooksSuccessful(-1978335189), isTrue);
    expect(wingetExitLooksSuccessful(0), isTrue);
    expect(wingetExitLooksSuccessful(1), isFalse);
  });
}
