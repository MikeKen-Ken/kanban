import type { ToolName } from "@cursor/sdk";

/**
 * Worker \u7981\u7528 MCP \u76EE\u5F55\u53D1\u73B0，\u5E76\u7528\u53EF\u6682\u505C\u7684 ask_user \u81EA\u5B9A\u4E49\u5DE5\u5177\u66FF\u4EE3\u65E0\u5934
 * askQuestion；\u4E0D\u7981 task。
 */
export const CURSOR_WORKER_DISALLOWED_TOOLS: ToolName[] = [
  "GetMcpTools",
  "askQuestion",
];

export const CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK: ToolName[] = [];

export function fallbackDisallowedTools(err: unknown): ToolName[] | null {
  const message = err instanceof Error ? err.message : String(err);
  if (!/GetMcpTools/i.test(message)) return null;
  return CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK;
}
