/** Worker \u6CE8\u5165\u7528\u6237 Rule \u65F6\u7684\u5305\u88F9\u8BB0\u53F7；SDK \u4E0D\u4F1A\u5199\u8FD9\u4E24\u884C。 */
export const WORKER_USER_RULES_BEGIN = "KANBAN_WORKER_USER_RULES_BEGIN";
export const WORKER_USER_RULES_END = "KANBAN_WORKER_USER_RULES_END";

/**
 * \u4EC5\u5B58\u5728\u4E8E\u7528\u6237\u89C4\u5219\u76EE\u5F55\u7684\u6821\u9A8C\u6587\u4EF6（alwaysApply: false）。
 * Worker \u4F1A\u590D\u5236\u5168\u6587；settingSources=project \u8FC7\u6EE4\u751F\u6548\u65F6 SDK \u4E0D\u5E94\u518D\u704C\u4E00\u6B21。
 */
export const USER_RULE_FILE_CANARY = "KANBAN_DISPATCH_USER_RULE_CANARY_A7F3";

/**
 * \u5199\u5728 alwaysApply \u7528\u6237\u89C4\u5219\u91CC\u7684\u6821\u9A8C\u6807\u8BB0。
 * Worker \u4F1A\u590D\u5236；\u82E5 SDK \u4ECD\u628A\u7528\u6237 alwaysApply \u89C4\u5219\u6CE8\u5165，\u4E0A\u4E0B\u6587\u91CC\u4F1A ≥2 \u6B21。
 */
export const ALWAYS_APPLY_USER_RULE_CANARY =
  "KANBAN_DISPATCH_ALWAYS_APPLY_CANARY_E91C";

export function wrapWorkerUserRules(text: string): string {
  const body = text.trim() || "No user ~/.cursor/rules found.";
  return [WORKER_USER_RULES_BEGIN, body, WORKER_USER_RULES_END].join("\n");
}
