import 'package:flutter/material.dart';

import '../mcp/mcp_git_commit.dart';
import 'agent_dispatch_field_style.dart';

/// 提交与推送（含 rebase）使用的 Git 作者身份。
class AgentDispatchGitAuthorFields extends StatelessWidget {
  const AgentDispatchGitAuthorFields({
    required this.nameController,
    required this.emailController,
    required this.enabled,
    required this.onNameChanged,
    required this.onEmailChanged,
    super.key,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final bool enabled;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onEmailChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: nameController,
            enabled: enabled,
            style: agentDispatchFieldTextStyle(theme),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              labelText: 'Commit author',
              hintText: defaultMcpGitAuthorName,
              hintStyle: agentDispatchFieldHintStyle(theme),
            ),
            onChanged: onNameChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: emailController,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            style: agentDispatchFieldTextStyle(theme),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              labelText: 'Author email',
              hintText: defaultMcpGitAuthorEmail,
              hintStyle: agentDispatchFieldHintStyle(theme),
            ),
            onChanged: onEmailChanged,
          ),
        ),
      ],
    );
  }
}
