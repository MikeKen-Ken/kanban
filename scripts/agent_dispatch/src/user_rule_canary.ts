/** Worker 注入用户 Rule 时的包裹记号；SDK 不会写这两行。 */
export const WORKER_USER_RULES_BEGIN = "KANBAN_WORKER_USER_RULES_BEGIN";
export const WORKER_USER_RULES_END = "KANBAN_WORKER_USER_RULES_END";

/**
 * 仅存在于用户规则目录的校验文件（alwaysApply: false）。
 * Worker 会复制全文；settingSources=project 过滤生效时 SDK 不应再灌一次。
 */
export const USER_RULE_FILE_CANARY = "KANBAN_DISPATCH_USER_RULE_CANARY_A7F3";

/**
 * 写在 alwaysApply 用户规则里的校验标记。
 * Worker 会复制；若 SDK 仍把用户 alwaysApply 规则注入，上下文里会 ≥2 次。
 */
export const ALWAYS_APPLY_USER_RULE_CANARY =
  "KANBAN_DISPATCH_ALWAYS_APPLY_CANARY_E91C";

export function wrapWorkerUserRules(text: string): string {
  const body = text.trim() || "未发现用户 ~/.cursor/rules。";
  return [WORKER_USER_RULES_BEGIN, body, WORKER_USER_RULES_END].join("\n");
}
