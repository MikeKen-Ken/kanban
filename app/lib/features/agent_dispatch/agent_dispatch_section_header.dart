import 'package:flutter/material.dart';

enum AgentDispatchSectionTone {
  configuration,
  account,
  queue,
  repository,
  identity,
  credential,
  worker,
  skill,
  log,
}

/// Agent 工作台各模块共用的标题样式。
class AgentDispatchSectionHeader extends StatelessWidget {
  const AgentDispatchSectionHeader({
    required this.title,
    required this.tone,
    super.key,
  });

  final String title;
  final AgentDispatchSectionTone tone;

  IconData get _icon => switch (tone) {
        AgentDispatchSectionTone.configuration => Icons.tune,
        AgentDispatchSectionTone.account => Icons.account_circle_outlined,
        AgentDispatchSectionTone.queue => Icons.playlist_play,
        AgentDispatchSectionTone.repository => Icons.folder_open_outlined,
        AgentDispatchSectionTone.identity => Icons.badge_outlined,
        AgentDispatchSectionTone.credential => Icons.key_outlined,
        AgentDispatchSectionTone.worker => Icons.handyman_outlined,
        AgentDispatchSectionTone.skill => Icons.auto_awesome_outlined,
        AgentDispatchSectionTone.log => Icons.receipt_long_outlined,
      };

  Color _accent(ColorScheme colors) => switch (tone) {
        AgentDispatchSectionTone.configuration => colors.primary,
        AgentDispatchSectionTone.account => colors.secondary,
        AgentDispatchSectionTone.queue => colors.tertiary,
        AgentDispatchSectionTone.repository => colors.primary,
        AgentDispatchSectionTone.identity => colors.secondary,
        AgentDispatchSectionTone.credential => colors.tertiary,
        AgentDispatchSectionTone.worker => colors.primary,
        AgentDispatchSectionTone.skill => colors.tertiary,
        AgentDispatchSectionTone.log => colors.error,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(theme.colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 17, color: accent),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
