import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// PowerShell 7 MSI 安装结果。
class PowerShellMsiInstallResult {
  const PowerShellMsiInstallResult({
    this.ok = false,
    this.log,
    this.error,
  });

  final bool ok;
  final String? log;
  final String? error;
}

typedef PowerShellReleaseFetcher = Future<String?> Function();
typedef HttpDownloadRunner = Future<void> Function({
  required String url,
  required String destination,
});
typedef MsiExecRunner = ({int exitCode, String stdout, String stderr}) Function(
  String msiPath,
);

/// 从 GitHub Release 解析 win-x64 MSI 下载地址；失败时返回 [fallbackMsiUrl]。
Future<String?> resolvePowerShellMsiDownloadUrl({
  PowerShellReleaseFetcher? fetchLatestRelease,
  String fallbackMsiUrl = powerShellMsiFallbackUrl,
}) async {
  final fetch = fetchLatestRelease ?? _fetchLatestReleaseMsiUrl;
  final resolved = await fetch();
  return resolved ?? fallbackMsiUrl;
}

/// 官方稳定版 MSI 回退地址（GitHub API 不可用时使用）。
const powerShellMsiFallbackUrl =
    'https://github.com/PowerShell/PowerShell/releases/download/v7.5.4/PowerShell-7.5.4-win-x64.msi';

Future<PowerShellMsiInstallResult> installPowerShell7ViaMsi({
  required Map<String, String> environment,
  required p.Context ctx,
  String? downloadUrl,
  PowerShellReleaseFetcher? fetchLatestRelease,
  HttpDownloadRunner? download,
  MsiExecRunner? msiexec,
  DirectoryExists? directoryExists,
}) async {
  final exists = directoryExists ?? (path) => Directory(path).existsSync();
  final tempRoot = _firstNonEmpty([
    _envValue(environment, 'TEMP'),
    _envValue(environment, 'TMP'),
  ]);
  if (tempRoot == null || tempRoot.trim().isEmpty) {
    return const PowerShellMsiInstallResult(
      error: 'Could not determine TEMP; cannot download the PowerShell MSI.',
    );
  }

  final url = downloadUrl ??
      await resolvePowerShellMsiDownloadUrl(
        fetchLatestRelease: fetchLatestRelease,
      );
  if (url == null || url.trim().isEmpty) {
    return const PowerShellMsiInstallResult(
      error: 'Could not resolve the PowerShell MSI download URL.',
    );
  }

  final tempDir =
      ctx.join(expandWindowsEnvVars(tempRoot, environment), 'kanban-pwsh');
  if (!exists(tempDir)) {
    try {
      await Directory(tempDir).create(recursive: true);
    } catch (error) {
      return PowerShellMsiInstallResult(
        error: 'Could not create temp directory $tempDir: $error',
      );
    }
  }

  final fileName = ctx.basename(Uri.parse(url).path);
  final msiPath = ctx.join(tempDir, fileName);
  try {
    final runDownload = download ?? _downloadFile;
    await runDownload(url: url, destination: msiPath);
  } catch (error) {
    return PowerShellMsiInstallResult(
      error: 'PowerShell MSI download failed: $error',
      log: 'url=$url',
    );
  }

  final runMsi = msiexec ?? _runMsiExec;
  final result = runMsi(msiPath);
  if (result.exitCode != 0 && result.exitCode != 3010) {
    return PowerShellMsiInstallResult(
      error: 'PowerShell MSI silent install failed (exit ${result.exitCode}). '
          'Administrator access may be required.',
      log: '${result.stdout} ${result.stderr}'.trim(),
    );
  }

  return PowerShellMsiInstallResult(
    ok: true,
    log: 'msi=$msiPath exit=${result.exitCode}',
  );
}

Future<String?> _fetchLatestReleaseMsiUrl() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
        'https://api.github.com/repos/PowerShell/PowerShell/releases/latest',
      ),
    );
    request.headers.set('User-Agent', 'kanban-agent-dispatch');
    request.headers.set('Accept', 'application/vnd.github+json');
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final assets = json['assets'];
    if (assets is! List) return null;
    for (final raw in assets) {
      if (raw is! Map<String, dynamic>) continue;
      final name = raw['name']?.toString() ?? '';
      final url = raw['browser_download_url']?.toString() ?? '';
      if (name.endsWith('-win-x64.msi') &&
          !name.contains('preview') &&
          url.isNotEmpty) {
        return url;
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> _downloadFile({
  required String url,
  required String destination,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', 'kanban-agent-dispatch');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final file = File(destination);
    final sink = file.openWrite();
    await response.pipe(sink);
    await sink.close();
  } finally {
    client.close(force: true);
  }
}

({int exitCode, String stdout, String stderr}) _runMsiExec(String msiPath) {
  try {
    final result = Process.runSync(
      'msiexec.exe',
      [
        '/i',
        msiPath,
        '/quiet',
        '/norestart',
        'ADD_PATH=1',
      ],
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  } catch (error) {
    return (exitCode: 1, stdout: '', stderr: error.toString());
  }
}

typedef DirectoryExists = bool Function(String path);

String? _envValue(Map<String, String> environment, String name) {
  final direct = environment[name];
  if (direct != null) return direct;
  for (final entry in environment.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return null;
}

String expandWindowsEnvVars(String raw, Map<String, String> environment) {
  if (!raw.contains('%')) return raw;
  return raw.replaceAllMapped(RegExp(r'%([^%]+)%'), (match) {
    final name = match.group(1)!;
    final value = _envValue(environment, name);
    return (value == null || value.isEmpty) ? match.group(0)! : value;
  });
}
