import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  CURSOR_WORKER_DISALLOWED_TOOLS,
  CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK,
  fallbackDisallowedTools,
} from "./cursor_disallowed_tools.ts";

describe("cursor_disallowed_tools", () => {
  it("禁用 GetMcpTools 与无头 askQuestion，不禁 task", () => {
    assert.deepEqual(CURSOR_WORKER_DISALLOWED_TOOLS, [
      "GetMcpTools",
      "askQuestion",
    ]);
    assert.equal(CURSOR_WORKER_DISALLOWED_TOOLS.includes("task"), false);
  });

  it("未知 GetMcpTools 名称时回退为不禁用", () => {
    assert.deepEqual(
      fallbackDisallowedTools(new Error("Unknown tool name: GetMcpTools")),
      CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK,
    );
    assert.equal(fallbackDisallowedTools(new Error("invalid model")), null);
  });
});
