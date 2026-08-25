import type { ToolName } from "@cursor/sdk";

/** Keep normal MCP catalog discovery; replace only the headless question tool. */
export const CURSOR_WORKER_DISALLOWED_TOOLS: ToolName[] = ["askQuestion"];

export const CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK: ToolName[] = [];

export function fallbackDisallowedTools(err: unknown): ToolName[] | null {
  const message = err instanceof Error ? err.message : String(err);
  if (!/askQuestion/i.test(message)) return null;
  return CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK;
}
