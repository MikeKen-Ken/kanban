import type { ToolName } from "@cursor/sdk";

/**
 * Worker 禁用 MCP 目录发现，并用可暂停的 ask_user 自定义工具替代无头
 * askQuestion；不禁 task。
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
