import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'agent_dispatch_usage.dart';

class AgentDispatchUsagePane extends StatelessWidget {
  const AgentDispatchUsagePane({
    required this.snapshot,
    required this.loading,
    this.onOpenTokenStats,
    super.key,
  });

  final AgentDispatchUsageSnapshot? snapshot;
  final bool loading;
  final VoidCallback? onOpenTokenStats;

  /// 额度接口缺失时的说明对工作台没有帮助，只保留真正的加载失败。
  static String _accountFallbackText(String? message) {
    final text = message?.trim() ?? '';
    if (text.contains('失败')) return text;
    return '尚未加载账号信息';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final email = snapshot?.userEmail?.trim();
    final keyName = snapshot?.apiKeyName?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Cursor 账号', style: textTheme.labelLarge),
            const Spacer(),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            TextButton(
              onPressed: onOpenTokenStats,
              child: const Text('Token 统计'),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://cursor.com/dashboard/usage'),
              ),
              child: const Text('Dashboard'),
            ),
          ],
        ),
        if (email != null && email.isNotEmpty)
          Text('邮箱：$email', style: textTheme.bodySmall),
        if (keyName != null && keyName.isNotEmpty)
          Text('Key：$keyName', style: textTheme.bodySmall),
        if ((email == null || email.isEmpty) &&
            (keyName == null || keyName.isEmpty) &&
            !loading)
          Text(
            _accountFallbackText(snapshot?.message),
            style: textTheme.bodySmall,
          ),
      ],
    );
  }
}
