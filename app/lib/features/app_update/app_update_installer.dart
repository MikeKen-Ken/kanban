import 'dart:convert';
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

  /// 将 [zipFile] 解压到临时目录并返回有效载荷根目录。
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
    return resolveWindowsPayloadRoot(out);
  }

  /// 若 zip 多包了一层目录，定位含可执行文件的实际根目录。
  @visibleForTesting
  static Future<Directory> resolveWindowsPayloadRoot(
    Directory extracted, {
    String? exeFileName,
  }) async {
    final exeName = exeFileName ??
        (Platform.isWindows
            ? p.basename(Platform.resolvedExecutable)
            : 'kanban.exe');
    final direct = File(p.join(extracted.path, exeName));
    if (await direct.exists()) return extracted;

    final children = await extracted.list().toList();
    final dirs = children.whereType<Directory>().toList();
    if (dirs.length == 1) {
      final nested = File(p.join(dirs.first.path, exeName));
      if (await nested.exists()) return dirs.first;
    }

    // 回退：任意一层子目录中找到同名 exe
    for (final dir in dirs) {
      final nested = File(p.join(dir.path, exeName));
      if (await nested.exists()) return dir;
    }
    return extracted;
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
    final payloadDir = await resolveWindowsPayloadRoot(extractedDir);
    final scriptFile = File(
      p.join(
        Directory.systemTemp.path,
        'kanban_updater_$pid.ps1',
      ),
    );
    // UTF-8 BOM：降低 PS 5.1 误用系统 ANSI 码页的风险；脚本本身保持 ASCII。
    await scriptFile.writeAsBytes(
      utf8.encode('\uFEFF$windowsUpdaterScript'),
      flush: true,
    );

    // 经 cmd start 拉起，避免随本进程 Job 对象一起被结束。
    await Process.start(
      'cmd.exe',
      [
        '/c',
        'start',
        '',
        '/min',
        'powershell.exe',
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
        payloadDir.path,
        '-ExePath',
        exePath,
        '-TargetPid',
        '$pid',
      ],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    // 给 updater 一点启动时间，再退出以释放文件锁
    await Future<void>.delayed(const Duration(milliseconds: 800));
    exit(0);
  }
}

/// Windows 自更新脚本（供单测在短路径 TEMP 下复现覆盖逻辑）。
///
/// **必须保持 ASCII**：Windows PowerShell 5.1 在 UTF-8（无/有 BOM）下解析含中文的
/// `.ps1` 可能直接 ParserError，导致不覆盖、不重启，且用户手动启动仍是旧版。
///
/// 安装目录 / 可执行文件路径均由调用方传入（当前进程的 exe 所在目录），
/// 不绑定固定盘符或用户目录。
@visibleForTesting
const windowsUpdaterScript = r'''
param(
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$ExePath,
  [Parameter(Mandatory = $true)][int]$TargetPid,
  [switch]$SkipLaunch
)
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP ("kanban_updater_" + $TargetPid + ".log")
function Write-Log([string]$msg) {
  $line = ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}
function Get-CanonicalPath([string]$Path) {
  return (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
}
function Get-RelativePathFrom([string]$Root, [string]$FullPath) {
  $rootUri = New-Object System.Uri (($Root.TrimEnd('\') + '\'))
  $fileUri = New-Object System.Uri $FullPath
  if (-not $rootUri.IsBaseOf($fileUri)) {
    throw "File not under source dir: $FullPath"
  }
  return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fileUri).ToString()).Replace('/', '\')
}
function Copy-FileWithRetry([string]$From, [string]$To) {
  $attempt = 0
  while ($true) {
    try {
      Copy-Item -LiteralPath $From -Destination $To -Force
      return
    } catch {
      $attempt++
      if ($attempt -ge 10) { throw }
      Start-Sleep -Milliseconds 500
    }
  }
}
try {
  Write-Log "Waiting for process exit PID=$TargetPid"
  $deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    Start-Sleep -Milliseconds 400
  }
  Start-Sleep -Seconds 2
  if (-not (Test-Path -LiteralPath $SourceDir)) {
    throw "Source dir missing: $SourceDir"
  }
  $InstallDir = Get-CanonicalPath $InstallDir
  $SourceDir = Get-CanonicalPath $SourceDir
  $ExePath = (Get-Item -LiteralPath $ExePath).FullName
  Write-Log "InstallDir=$InstallDir"
  Write-Log "SourceDir=$SourceDir"
  Write-Log "ExePath=$ExePath"
  Write-Log "Copy start"
  $copied = 0
  Get-ChildItem -LiteralPath $SourceDir -Recurse -File | ForEach-Object {
    $rel = Get-RelativePathFrom $SourceDir $_.FullName
    if ([string]::IsNullOrWhiteSpace($rel)) { return }
    if ($rel -ieq 'settings.json') { return }
    $dest = Join-Path $InstallDir $rel
    $destParent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $destParent)) {
      New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    Copy-FileWithRetry $_.FullName $dest
    $copied++
  }
  if ($copied -le 0) {
    throw "No files copied from source dir"
  }
  if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "Exe missing after copy: $ExePath"
  }
  Write-Log "Copied $copied files"
  if (-not $SkipLaunch) {
    Write-Log "Launch $ExePath cwd=$InstallDir"
    Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir
  } else {
    Write-Log "SkipLaunch"
  }
  Write-Log "Cleanup"
  Remove-Item -LiteralPath $SourceDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Write-Log ("Update failed: " + $_.Exception.Message)
  exit 1
} finally {
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
''';
