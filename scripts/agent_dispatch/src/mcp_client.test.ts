import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { CallToolResult } from "@modelcontextprotocol/client";
import { parseClaimResult, withTimeout } from "./mcp_client.ts";

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
});
