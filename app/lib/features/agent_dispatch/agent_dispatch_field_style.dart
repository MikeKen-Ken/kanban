import 'package:flutter/material.dart';

/// Agent 工具台输入框文字：比占位符更深，避免与 hint 颜色接近。
TextStyle agentDispatchFieldTextStyle(ThemeData theme) {
  return (theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16)).copyWith(
    color: theme.colorScheme.onSurface,
    fontWeight: FontWeight.w500,
  );
}

/// Agent 工具台占位符：更浅、更透明，与已输入内容分层。
TextStyle agentDispatchFieldHintStyle(ThemeData theme) {
  return (theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16)).copyWith(
    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
    fontWeight: FontWeight.w400,
  );
}
