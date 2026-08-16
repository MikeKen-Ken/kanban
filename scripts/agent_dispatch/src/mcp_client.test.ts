import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { CallToolResult } from "@modelcontextprotocol/client";
import {
  MCP_CLAIM_TIMEOUT_MS,
  MCP_FINALIZE_TIMEOUT_MS,
  mcpTimeoutForTool,
  parseClaimResult,
  withTimeout,
} from "./mcp_client.ts";

describe("mcp_client", () => {
  it("同时解析 claim JSON 与 ImageContent", () => {
    const result = {
      content: [
        { type: "text", text: '{"found":true,"cardId":"card-a"}' },
        { type: "image", data: "aGVsbG8=", mimeType: "image/png" },
      ],
    } as CallToolResult;

    const parsed = parseClaimResult(result);

    assert.equal(parsed.payload.cardId, "card-a");
    assert.deepEqual(parsed.images, [
      { data: "aGVsbG8=", mimeType: "image/png" },
    ]);
  });

  it("MCP 操作超时后拒绝", async () => {
    await assert.rejects(
      withTimeout("测试调用", 10, new Promise(() => undefined)),
      /测试调用 超时/,
    );
  });

  it("按工具名选择 claim/finalize 超时", () => {
    assert.equal(mcpTimeoutForTool("dispatch_claim_next_card"), MCP_CLAIM_TIMEOUT_MS);
    assert.equal(mcpTimeoutForTool("dispatch_finalize"), MCP_FINALIZE_TIMEOUT_MS);
    assert.equal(mcpTimeoutForTool("peek_next_card"), 30_000);
    assert.equal(mcpTimeoutForTool("get_card"), 30_000);
  });
});
