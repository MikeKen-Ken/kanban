import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'agent_dispatch_usage.dart';

class AgentDispatchUsagePane extends StatelessWidget {
  const AgentDispatchUsagePane({
    required this.snapshot,
    required this.loading,
    required this.enabled,
    required this.onRefresh,
    super.key,
  });

  final AgentDispatchUsageSnapshot? snapshot;
  final bool loading;
  final bool enabled;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('额度', style: textTheme.labelLarge),
            const Spacer(),
            TextButton(
              onPressed: enabled && !loading ? onRefresh : null,
              child: Text(loading ? '刷新中…' : '刷新额度'),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://cursor.com/dashboard/usage'),
              ),
              child: const Text('Dashboard'),
            ),
          ],
        ),
        if (snapshot?.userEmail != null || snapshot?.apiKeyName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              [
                if (snapshot?.userEmail != null) snapshot!.userEmail,
                if (snapshot?.apiKeyName != null) snapshot!.apiKeyName,
              ].join(' · '),
              style: textTheme.bodySmall,
            ),
          ),
        _UsageBar(
          label: 'Auto + Composer',
          remainingPercent: snapshot?.autoRemainingPercent,
        ),
        const SizedBox(height: 6),
        _UsageBar(
          label: 'API 模型',
          remainingPercent: snapshot?.apiRemainingPercent,
        ),
        if (snapshot?.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(snapshot!.message!, style: textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.label, required this.remainingPercent});

  final String label;
  final double? remainingPercent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final remaining = remainingPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: textTheme.bodySmall)),
            Text(
              remaining == null ? '暂无数据' : '剩余 ${remaining.round()}%',
              style: textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: remaining == null ? 0 : (remaining / 100).clamp(0, 1),
        ),
      ],
    );
  }
}
