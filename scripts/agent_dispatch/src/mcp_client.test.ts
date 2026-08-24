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
  it("\u540C\u65F6\u89E3\u6790 claim JSON \u4E0E ImageContent", () => {
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

  it("MCP \u64CD\u4F5C\u8D85\u65F6\u540E\u62D2\u7EDD", async () => {
    await assert.rejects(
      withTimeout("\u6D4B\u8BD5\u8C03\u7528", 10, new Promise(() => undefined)),
      /\u6D4B\u8BD5\u8C03\u7528 timed out/,
    );
  });

  it("\u6309\u5DE5\u5177\u540D\u9009\u62E9 claim/finalize \u8D85\u65F6", () => {
    assert.equal(mcpTimeoutForTool("dispatch_claim_next_card"), MCP_CLAIM_TIMEOUT_MS);
    assert.equal(mcpTimeoutForTool("dispatch_finalize"), MCP_FINALIZE_TIMEOUT_MS);
    assert.equal(mcpTimeoutForTool("peek_next_card"), 30_000);
    assert.equal(mcpTimeoutForTool("get_card"), 30_000);
  });
});
