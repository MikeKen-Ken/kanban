import {
  Client,
  StreamableHTTPClientTransport,
  type CallToolResult,
} from "@modelcontextprotocol/client";
import { settleWithin } from "./async_limit.ts";
import type { RoundImage } from "./types.ts";

const DEFAULT_MCP_TIMEOUT_MS = 30_000;
export const MCP_CLAIM_TIMEOUT_MS = 120_000;
export const MCP_FINALIZE_TIMEOUT_MS = 10 * 60_000;

export function mcpTimeoutForTool(name: string): number {
  switch (name) {
    case "dispatch_claim_next_card":
      return MCP_CLAIM_TIMEOUT_MS;
    case "dispatch_finalize":
      return MCP_FINALIZE_TIMEOUT_MS;
    default:
      return DEFAULT_MCP_TIMEOUT_MS;
  }
}

export type ParsedClaimResult = {
  payload: Record<string, unknown>;
  images: RoundImage[];
  raw: CallToolResult;
};

export interface KanbanMcpConnection {
  listTools(): Promise<string[]>;
  callRaw(
    name: string,
    args: Record<string, unknown>,
    options?: { timeoutMs?: number },
  ): Promise<CallToolResult>;
  callJson(
    name: string,
    args: Record<string, unknown>,
    options?: { timeoutMs?: number },
  ): Promise<Record<string, unknown>>;
  close(): Promise<void>;
}

export class KanbanMcpClient implements KanbanMcpConnection {
  private readonly client = new Client({
    name: "kanban-agent-worker",
    version: "1.0.0",
  });
  private connected = false;
  private readonly timeoutMs: number;

  constructor(timeoutMs = DEFAULT_MCP_TIMEOUT_MS) {
    this.timeoutMs = timeoutMs;
  }

  async connect(endpoint: string): Promise<void> {
    await withTimeout(
      "Connect MCP",
      this.timeoutMs,
      this.client.connect(
        new StreamableHTTPClientTransport(new URL(endpoint)),
      ),
    );
    this.connected = true;
  }

  async listTools(): Promise<string[]> {
    const result = await withTimeout(
      "List MCP tools",
      this.timeoutMs,
      this.client.listTools(),
    );
    return result.tools.map((tool) => tool.name).sort();
  }

  async callRaw(
    name: string,
    args: Record<string, unknown>,
    options?: { timeoutMs?: number },
  ): Promise<CallToolResult> {
    const result = await withTimeout(
      `Call ${name}`,
      options?.timeoutMs ?? mcpTimeoutForTool(name),
      this.client.callTool({ name, arguments: args }),
    );
    if (result.isError) {
      throw new Error(`${name} failed: ${resultText(result)}`);
    }
    return result;
  }

  async callJson(
    name: string,
    args: Record<string, unknown>,
    options?: { timeoutMs?: number },
  ): Promise<Record<string, unknown>> {
    const result = await this.callRaw(name, args, options);
    const text = resultText(result);
    try {
      return JSON.parse(text) as Record<string, unknown>;
    } catch {
      throw new Error(`${name} returned invalid JSON: ${text}`);
    }
  }

  async close(): Promise<void> {
    if (!this.connected) return;
    this.connected = false;
    // Streamable HTTP / SSE 的 close 可能一直等不到服务端结束流。
    await settleWithin(2000, this.client.close());
  }
}

export function parseClaimResult(result: CallToolResult): ParsedClaimResult {
  const text = resultText(result);
  let payload: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("JSON top-level value is not an object");
    }
    payload = parsed as Record<string, unknown>;
  } catch (error) {
    throw new Error(
      `dispatch_claim_next_card returned invalid JSON: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  const images = result.content
    .filter(
      (item): item is Extract<
        (typeof result.content)[number],
        { type: "image" }
      > => item.type === "image",
    )
    .map((item) => ({ data: item.data, mimeType: item.mimeType }));
  return { payload, images, raw: result };
}

export function resultText(result: CallToolResult): string {
  return result.content
    .filter(
      (item): item is Extract<
        (typeof result.content)[number],
        { type: "text" }
      > => item.type === "text",
    )
    .map((item) => item.text)
    .join("\n")
    .trim();
}

export async function withTimeout<T>(
  operation: string,
  timeoutMs: number,
  work: Promise<T>,
): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      work,
      new Promise<T>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error(`${operation} timed out (${timeoutMs}ms)`)),
          timeoutMs,
        );
        timer.unref?.();
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}
