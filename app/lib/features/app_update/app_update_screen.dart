import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../settings/settings_section.dart';
import 'app_update_service.dart';
import 'github_release_models.dart';
import 'version_compare.dart';
import '../../common/app_snack_bar.dart';

/// 检查并安装来自 GitHub Release 的更新。
class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key, this.service});

  final AppUpdateService? service;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  late final AppUpdateService _service;
  late final bool _ownsService;
  PackageInfo? _info;
  DateTime? _installedPublishedAt;
  AppUpdateCheckResult? _check;
  String? _error;
  bool _busy = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? AppUpdateService();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final installedAt = await _service.installedReleasePublishedAt();
    if (!mounted) return;
    setState(() {
      _info = info;
      _installedPublishedAt = installedAt;
    });
    await _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      final result = await _service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _check = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _install() async {
    final check = _check;
    if (check == null || !check.updateAvailable) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      await _service.downloadAndInstall(
        check,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnackBar(context, message: '已调起安装；完成后请按提示完成更新');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final check = _check;
    final currentDate = _currentVersionDate(check);
    final currentDateText = formatAppUpdateDate(currentDate);
    final versionLabel = info == null
        ? '读取中…'
        : currentDateText.isEmpty
            ? '${info.version}（${info.buildNumber}）'
            : '${info.version}（${info.buildNumber}）\n发布于 $currentDateText';
    final remote = check?.release;
    final remoteDateText = formatAppUpdateDate(
      remote?.displayDate ?? check?.asset?.updatedAt,
    );
    final remoteTitle = remote == null
        ? ''
        : '远端 ${remote.versionLabel}（${remote.tagName}）';
    final remoteSubtitleParts = <String>[
      if (remoteDateText.isNotEmpty) '发布于 $remoteDateText',
      if (check?.updateAvailable == true)
        (check?.message?.contains('同版本') == true ? '同版本安装包已刷新' : '有可用更新')
      else
        '已是最新',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('检查更新')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSection(
            icon: Icons.system_update_alt_outlined,
            title: '软件更新',
            subtitle: '从 GitHub Release 获取安装包',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('当前版本'),
                subtitle: Text(versionLabel),
              ),
              if (remote != null)
                ListTile(
                  leading: const Icon(Icons.new_releases_outlined),
                  title: Text(remoteTitle),
                  subtitle: Text(remoteSubtitleParts.join('\n')),
                ),
              if (_progress != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(
                        value: _progress,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (_progress ?? 0) >= 0.999
                            ? '下载完成，正在解压安装…请勿关闭窗口'
                            : '下载 ${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _checkUpdate,
                        child: const Text('重新检查'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ||
                                check == null ||
                                !check.updateAvailable ||
                                !_service.isSupported
                            ? null
                            : _install,
                        child: Text(
                          check?.updateAvailable == true ? '下载并安装' : '无需更新',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (check?.release?.body.trim().isNotEmpty == true) ...[
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.notes_outlined,
              title: '更新说明',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SelectableText(check!.release!.body.trim()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  DateTime? _currentVersionDate(AppUpdateCheckResult? check) {
    if (_installedPublishedAt != null) return _installedPublishedAt;
    final info = _info;
    final release = check?.release;
    if (info == null || release == null) return null;
    if (VersionCompare.compare(release.versionLabel, info.version) != 0) {
      return null;
    }
    return release.displayDate ?? check?.asset?.updatedAt;
  }
}

/// 启动时若有更新则提示（可跳过该版本）。
Future<void> maybePromptAppUpdate(BuildContext context) async {
  final service = AppUpdateService();
  try {
    if (!service.isSupported) return;
    final result = await service.checkForUpdate();
    if (!result.updateAvailable || result.release == null) return;
    final skipped = await service.skippedVersion();
    if (skipped != null &&
        skipped == result.release!.versionLabel &&
        // 同版本刷新包仍提示
        result.message?.contains('同版本') != true) {
      return;
    }
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('发现新版本 ${result.release!.versionLabel}'),
        content: Text(_startupPromptBody(result)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('跳过此版本'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: const Text('去更新'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'skip') {
      await service.skipVersion(result.release!.versionLabel);
    } else if (action == 'update') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AppUpdateScreen(service: service),
        ),
      );
      return;
    }
  } catch (_) {
    // 启动检查失败静默忽略
  } finally {
    service.dispose();
  }
}

String _startupPromptBody(AppUpdateCheckResult result) {
  final date = formatAppUpdateDate(
    result.release?.displayDate ?? result.asset?.updatedAt,
  );
  final message = result.message ?? '是否前往更新？';
  if (date.isEmpty) return message;
  if (message.contains(date)) return message;
  return '$message\n发布于 $date';
}
