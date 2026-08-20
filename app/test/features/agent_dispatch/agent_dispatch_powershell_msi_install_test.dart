import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/agent_dispatch/agent_dispatch_powershell_msi_install.dart';
import 'package:path/path.dart' as p;

void main() {
  test('GitHub API 返回的资产可解析为 win-x64 MSI', () async {
    final url = await resolvePowerShellMsiDownloadUrl(
      fetchLatestRelease: () async =>
          'https://github.com/PowerShell/PowerShell/releases/download/v7.6.5/PowerShell-7.6.5-win-x64.msi',
    );
    expect(url, contains('win-x64.msi'));
  });

  test('GitHub API 不可用时使用回退 MSI 地址', () async {
    final url = await resolvePowerShellMsiDownloadUrl(
      fetchLatestRelease: () async => null,
    );
    expect(url, powerShellMsiFallbackUrl);
  });

  test('MSI 安装成功', () async {
    const pwsh = r'C:\Program Files\PowerShell\7\pwsh.exe';
    var downloaded = false;
    var installed = false;
    final result = await installPowerShell7ViaMsi(
      environment: const {'TEMP': r'C:\Temp'},
      ctx: p.Context(style: p.Style.windows),
      downloadUrl: 'https://example.com/PowerShell-7.6.5-win-x64.msi',
      directoryExists: (_) => true,
      download: ({required url, required destination}) async {
        downloaded = true;
        expect(url, contains('PowerShell'));
      },
      msiexec: (path) {
        installed = true;
        expect(path, contains('PowerShell-7.6.5-win-x64.msi'));
        return (exitCode: 0, stdout: '', stderr: '');
      },
    );

    expect(downloaded, isTrue);
    expect(installed, isTrue);
    expect(result.ok, isTrue);
  });
}
