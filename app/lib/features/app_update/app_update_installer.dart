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
    final relaunchFile = File(
      p.join(Directory.systemTemp.path, 'kanban_relaunch_$pid.ps1'),
    );
    await relaunchFile.writeAsBytes(
      utf8.encode('\uFEFF$windowsRelaunchScript'),
      flush: true,
    );

    // 经 cmd start 拉起，避免随本进程 Job 对象一起被结束。
    // 仅由 relaunch 脚本启动应用，避免 updater finally 与 relaunch 各拉起一次导致双窗口。
    await _startDetachedPowershell(
      scriptPath: scriptFile.path,
      extraArgs: [
        '-InstallDir',
        installDir,
        '-SourceDir',
        payloadDir.path,
        '-ExePath',
        exePath,
        '-TargetPid',
        '$pid',
        '-SkipLaunch',
      ],
    );
    // 独立拉起：复制失败或 updater 被提前结束时，仍根据日志/超时重启界面。
    await _startDetachedPowershell(
      scriptPath: relaunchFile.path,
      extraArgs: [
        '-InstallDir',
        installDir,
        '-ExePath',
        exePath,
        '-TargetPid',
        '$pid',
      ],
    );

    // 给 updater 一点启动时间，再退出以释放文件锁
    await Future<void>.delayed(const Duration(milliseconds: 800));
    exit(0);
  }
}

Future<void> _startDetachedPowershell({
  required String scriptPath,
  required List<String> extraArgs,
}) {
  return Process.start(
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
      scriptPath,
      ...extraArgs,
    ],
    mode: ProcessStartMode.detached,
    runInShell: false,
  );
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
function Stop-LockingPids([string]$FilePath) {
  if (-not (Test-Path -LiteralPath $FilePath)) { return }
  if (-not ('NativeRm' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeRm {
  public const int CCH = 255;
  [StructLayout(LayoutKind.Sequential)]
  public struct RM_UNIQUE_PROCESS {
    public int dwProcessId;
    public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
  }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct RM_PROCESS_INFO {
    public RM_UNIQUE_PROCESS Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
    public string strAppName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
    public string strServiceShortName;
    public uint ApplicationType;
    public uint AppStatus;
    public uint TSSessionId;
    [MarshalAs(UnmanagedType.Bool)]
    public bool bRestartable;
  }
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmEndSession(uint pSessionHandle);
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, IntPtr rgApplications, uint nServices, string[] rgsServiceNames);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);
}
'@
  }
  $session = [uint32]0
  $key = [guid]::NewGuid().ToString()
  $rc = [NativeRm]::RmStartSession([ref]$session, 0, $key)
  if ($rc -ne 0) { return }
  try {
    $rc = [NativeRm]::RmRegisterResources($session, 1, @($FilePath), 0, [IntPtr]::Zero, 0, $null)
    if ($rc -ne 0) { return }
    $needed = [uint32]0
    $count = [uint32]0
    $reason = [uint32]0
    $rc = [NativeRm]::RmGetList($session, [ref]$needed, [ref]$count, $null, [ref]$reason)
    if ($needed -le 0) { return }
    $arr = New-Object NativeRm+RM_PROCESS_INFO[] $needed
    $count = $needed
    $rc = [NativeRm]::RmGetList($session, [ref]$needed, [ref]$count, $arr, [ref]$reason)
    if ($rc -ne 0) { return }
    foreach ($info in $arr) {
      $lockPid = $info.Process.dwProcessId
      if ($lockPid -eq $PID -or $lockPid -le 0) { continue }
      Write-Log "Stopping lock PID=$lockPid ($($info.strAppName)) for $FilePath"
      Stop-Process -Id $lockPid -Force -ErrorAction SilentlyContinue
    }
  } finally {
    [NativeRm]::RmEndSession($session) | Out-Null
  }
}
function Start-KanbanApp([string]$Exe, [string]$Dir) {
  if (-not (Test-Path -LiteralPath $Exe)) { return }
  $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.Equals($Exe, [StringComparison]::OrdinalIgnoreCase)
  })
  if ($running.Count -gt 0) {
    Write-Log "Already running"
    return
  }
  Write-Log "Launch $Exe cwd=$Dir"
  $d = $Dir.TrimEnd('\')
  $line = '/c start "" /D "' + $d + '" "' + $Exe + '"'
  Start-Process -FilePath 'cmd.exe' -ArgumentList $line -WindowStyle Hidden
}
function Copy-FileWithRetry([string]$From, [string]$To, [bool]$AllowSkip) {
  $attempt = 0
  while ($true) {
    try {
      Copy-Item -LiteralPath $From -Destination $To -Force
      return
    } catch {
      $attempt++
      try { Stop-LockingPids $To } catch { }
      if ($attempt -ge 10) {
        if ($AllowSkip) {
          Write-Log ("Skip locked file " + $To)
          return
        }
        throw
      }
      Start-Sleep -Milliseconds 500
    }
  }
}
function Test-IsAgentWorkerRel([string]$Rel) {
  return $Rel -like 'agent_worker\*' -or $Rel -like 'agent_worker/*' -or $Rel -ieq 'agent_worker'
}
function Get-AgentWorkerPids([string]$WorkerDir) {
  $workerRoot = (Get-CanonicalPath $WorkerDir).TrimEnd('\')
  $ids = @{}
  Get-CimInstance Win32_Process | ForEach-Object {
    if ($_.ProcessId -eq $PID) { return }
    $hit = $false
    if ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($workerRoot, [StringComparison]::OrdinalIgnoreCase)) {
      $hit = $true
    }
    if (-not $hit -and $_.CommandLine) {
      if ($_.CommandLine.IndexOf($workerRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
      if (-not $hit -and $_.CommandLine.IndexOf('\agent_worker\', [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
    }
    if ($hit) { $ids[$_.ProcessId] = $true }
  }
  Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Id -eq $PID) { return }
    try {
      foreach ($m in $_.Modules) {
        if ($m.FileName -and $m.FileName.StartsWith($workerRoot, [StringComparison]::OrdinalIgnoreCase)) {
          $ids[$_.Id] = $true
          break
        }
      }
    } catch {}
  }
  return @($ids.Keys)
}
function Stop-AgentWorkerProcesses([string]$InstallDir) {
  $workerDir = Join-Path $InstallDir 'agent_worker'
  if (-not (Test-Path -LiteralPath $workerDir)) { return }
  Write-Log "Stopping agent workers under $workerDir"
  foreach ($wid in (Get-AgentWorkerPids $workerDir)) {
    Write-Log "Stopping agent worker PID=$wid"
    Stop-Process -Id $wid -Force -ErrorAction SilentlyContinue
  }
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    if ((Get-AgentWorkerPids $workerDir).Count -eq 0) { return }
    Start-Sleep -Milliseconds 300
  }
  Write-Log "Agent worker still running; continue with app file copy"
}
function Copy-PayloadFiles([bool]$WorkerOnly) {
  $n = 0
  Get-ChildItem -LiteralPath $SourceDir -Recurse -File | ForEach-Object {
    $rel = Get-RelativePathFrom $SourceDir $_.FullName
    if ([string]::IsNullOrWhiteSpace($rel)) { return }
    if ($rel -ieq 'settings.json') { return }
    $isWorker = Test-IsAgentWorkerRel $rel
    if ($WorkerOnly -ne $isWorker) { return }
    $dest = Join-Path $InstallDir $rel
    $destParent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $destParent)) {
      New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    Copy-FileWithRetry $_.FullName $dest $WorkerOnly
    $n++
  }
  return $n
}
$failed = $false
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
  Write-Log "Copy app files"
  $copied = Copy-PayloadFiles $false
  Stop-AgentWorkerProcesses $InstallDir
  Write-Log "Copy agent worker"
  try {
    $copied = $copied + (Copy-PayloadFiles $true)
  } catch {
    Write-Log ("Agent worker copy failed: " + $_.Exception.Message)
    $appSo = Join-Path $InstallDir 'data\app.so'
    if (-not (Test-Path -LiteralPath $ExePath)) { throw }
    if (-not (Test-Path -LiteralPath $appSo)) { throw }
    Write-Log "Continue launch; agent worker left unchanged"
  }
  if ($copied -le 0) {
    throw "No files copied from source dir"
  }
  if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "Exe missing after copy: $ExePath"
  }
  Write-Log "Copied $copied files"
  if ($SkipLaunch) {
    Write-Log "SkipLaunch"
  }
  Write-Log "Cleanup"
  Remove-Item -LiteralPath $SourceDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Write-Log ("Update failed: " + $_.Exception.Message)
  $failed = $true
} finally {
  if (-not $SkipLaunch) {
    try { Start-KanbanApp $ExePath $InstallDir } catch { }
  }
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
if ($failed) { exit 1 }
''';

/// 与 updater 分开拉起，避免复制失败或 `exit` 跳过 finally 时窗口不再出现。
@visibleForTesting
const windowsRelaunchScript = r'''
param(
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$ExePath,
  [Parameter(Mandatory = $true)][int]$TargetPid
)
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP ("kanban_relaunch_" + $TargetPid + ".log")
$updLog = Join-Path $env:TEMP ("kanban_updater_" + $TargetPid + ".log")
function Write-Log([string]$msg) {
  $line = ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}
function Start-KanbanApp([string]$Exe, [string]$Dir) {
  if (-not (Test-Path -LiteralPath $Exe)) { return }
  $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.Equals($Exe, [StringComparison]::OrdinalIgnoreCase)
  })
  if ($running.Count -gt 0) {
    Write-Log "Already running"
    return
  }
  Write-Log "Launch $Exe cwd=$Dir"
  $d = $Dir.TrimEnd('\')
  $line = '/c start "" /D "' + $d + '" "' + $Exe + '"'
  Start-Process -FilePath 'cmd.exe' -ArgumentList $line -WindowStyle Hidden
}
try {
  Write-Log "Waiting for process exit PID=$TargetPid"
  $deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 400
  }
  $deadline = (Get-Date).AddSeconds(180)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $updLog) {
      $text = Get-Content -LiteralPath $updLog -Raw -ErrorAction SilentlyContinue
      if ($text -and ($text -match 'Copied \d+ files' -or $text -match 'Update failed' -or $text -match 'SkipLaunch' -or $text -match 'Continue launch')) {
        break
      }
    }
    Start-Sleep -Milliseconds 400
  }
  Start-Sleep -Seconds 1
  Start-KanbanApp $ExePath $InstallDir
  Write-Log "Done"
} catch {
  Write-Log ("Relaunch failed: " + $_.Exception.Message)
  try { Start-KanbanApp $ExePath $InstallDir } catch { }
} finally {
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
''';
