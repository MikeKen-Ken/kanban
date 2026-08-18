import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  CURSOR_WORKER_DISALLOWED_TOOLS,
  CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK,
  fallbackDisallowedTools,
} from "./cursor_disallowed_tools.ts";

describe("cursor_disallowed_tools", () => {
  it("优先禁用 task 与 GetMcpTools", () => {
    assert.deepEqual(CURSOR_WORKER_DISALLOWED_TOOLS, ["task", "GetMcpTools"]);
  });

  it("未知 GetMcpTools 名称时回退为只禁 task", () => {
    assert.deepEqual(
      fallbackDisallowedTools(new Error("Unknown tool name: GetMcpTools")),
      CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK,
    );
    assert.equal(fallbackDisallowedTools(new Error("invalid model")), null);
  });
});
