import type { ToolName } from "@cursor/sdk";

/** Worker 默认禁用：子 Agent，以及会把 MCP 全表 schema 拉进上下文的发现工具。 */
export const CURSOR_WORKER_DISALLOWED_TOOLS: ToolName[] = [
  "task",
  "GetMcpTools",
];

export const CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK: ToolName[] = ["task"];

export function fallbackDisallowedTools(err: unknown): ToolName[] | null {
  const message = err instanceof Error ? err.message : String(err);
  if (!/GetMcpTools/i.test(message)) return null;
  return CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK;
}
