import type { ToolName } from "@cursor/sdk";

/** Worker 禁用 MCP 目录发现，避免整表 schema 进上下文。不禁 task。 */
export const CURSOR_WORKER_DISALLOWED_TOOLS: ToolName[] = ["GetMcpTools"];

export const CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK: ToolName[] = [];

export function fallbackDisallowedTools(err: unknown): ToolName[] | null {
  const message = err instanceof Error ? err.message : String(err);
  if (!/GetMcpTools/i.test(message)) return null;
  return CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK;
}
