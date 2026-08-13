import {
  Client,
  StreamableHTTPClientTransport,
  type CallToolResult,
} from "@modelcontextprotocol/client";
import { settleWithin } from "./async_limit.js";

export class KanbanMcpClient {
  private readonly client = new Client({
    name: "kanban-agent-worker",
    version: "1.0.0",
  });

  async connect(endpoint: string): Promise<void> {
    await this.client.connect(
      new StreamableHTTPClientTransport(new URL(endpoint)),
    );
  }

  async callJson(
    name: string,
    args: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const result = await this.client.callTool({ name, arguments: args });
    if (result.isError) {
      throw new Error(`${name} 失败：${this.resultText(result)}`);
    }
    const text = this.resultText(result);
    try {
      return JSON.parse(text) as Record<string, unknown>;
    } catch {
      throw new Error(`${name} 返回了无效 JSON：${text}`);
    }
  }

  async close(): Promise<void> {
    // Streamable HTTP / SSE 的 close 可能一直等不到服务端结束流。
    await settleWithin(2000, this.client.close());
  }

  private resultText(result: CallToolResult): string {
    return result.content
      .filter(
        (item): item is Extract<(typeof result.content)[number], { type: "text" }> =>
          item.type === "text",
      )
      .map((item) => item.text)
      .join("\n")
      .trim();
  }
}
