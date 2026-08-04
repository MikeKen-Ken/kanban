import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 平台安装：Android 调起 APK 安装器；Windows 写 updater 并退出替换。
class AppUpdateInstaller {
  AppUpdateInstaller({MethodChannel? androidChannel})
      : _androidChannel = androidChannel ??
            const MethodChannel('com.mikeken.kanban/app_update');

  final MethodChannel _androidChannel;

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isWindows;
  }

  /// 将 [zipFile] 解压到临时目录并返回该目录。
  Future<Directory> extractZip(File zipFile) async {
    final tempRoot = await getTemporaryDirectory();
    final out = Directory(
      p.join(
        tempRoot.path,
        'kanban_update_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    if (await out.exists()) {
      await out.delete(recursive: true);
    }
    await out.create(recursive: true);
    await extractFileToDisk(zipFile.path, out.path);
    return out;
  }

  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return true;
    final result =
        await _androidChannel.invokeMethod<bool>('canRequestPackageInstalls');
    return result ?? false;
  }

  Future<void> openUnknownSourcesSettings() async {
    if (!Platform.isAndroid) return;
    await _androidChannel.invokeMethod<void>('openUnknownSourcesSettings');
  }

  Future<void> installAndroidApk(File apkFile) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('仅 Android 支持 APK 安装');
    }
    final allowed = await canRequestPackageInstalls();
    if (!allowed) {
      await openUnknownSourcesSettings();
      throw StateError('请允许安装未知应用后再次点击更新');
    }
    await _androidChannel.invokeMethod<void>('installApk', {
      'path': apkFile.path,
    });
  }

  /// 启动 PowerShell updater，等待本进程退出后覆盖安装目录并重启。
  Future<void> applyWindowsZipUpdate(Directory extractedDir) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('仅 Windows 支持 zip 自更新');
    }
    final exePath = Platform.resolvedExecutable;
    final installDir = File(exePath).parent.path;
    final scriptFile = File(
      p.join(
        Directory.systemTemp.path,
        'kanban_updater_$pid.ps1',
      ),
    );
    await scriptFile.writeAsString(_windowsUpdaterScript, flush: true);

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptFile.path,
        '-InstallDir',
        installDir,
        '-SourceDir',
        extractedDir.path,
        '-ExePath',
        exePath,
        '-TargetPid',
        '$pid',
      ],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    // 给 updater 一点启动时间，再退出以释放文件锁
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }
}

const _windowsUpdaterScript = r'''
param(
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$ExePath,
  [Parameter(Mandatory = $true)][int]$TargetPid
)
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP ("kanban_updater_" + $TargetPid + ".log")
function Write-Log([string]$msg) {
  $line = ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}
try {
  Write-Log "等待进程退出 PID=$TargetPid"
  $deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    Start-Sleep -Milliseconds 400
  }
  Start-Sleep -Seconds 1
  if (-not (Test-Path -LiteralPath $SourceDir)) {
    throw "源目录不存在: $SourceDir"
  }
  Write-Log "开始复制到 $InstallDir"
  Get-ChildItem -LiteralPath $SourceDir -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring((Resolve-Path -LiteralPath $SourceDir).Path.Length).TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($rel)) { return }
    # 不覆盖本机旁路文件（若有）
    if ($rel -ieq 'settings.json') { return }
    $dest = Join-Path $InstallDir $rel
    $destParent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $destParent)) {
      New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
  }
  Write-Log "启动 $ExePath"
  Start-Process -FilePath $ExePath
  Write-Log "清理临时文件"
  Remove-Item -LiteralPath $SourceDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Write-Log ("更新失败: " + $_.Exception.Message)
  exit 1
} finally {
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
''';
