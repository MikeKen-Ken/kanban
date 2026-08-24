import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  CURSOR_WORKER_DISALLOWED_TOOLS,
  CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK,
  fallbackDisallowedTools,
} from "./cursor_disallowed_tools.ts";

describe("cursor_disallowed_tools", () => {
  it("\u7981\u7528 GetMcpTools \u4E0E\u65E0\u5934 askQuestion，\u4E0D\u7981 task", () => {
    assert.deepEqual(CURSOR_WORKER_DISALLOWED_TOOLS, [
      "GetMcpTools",
      "askQuestion",
    ]);
    assert.equal(CURSOR_WORKER_DISALLOWED_TOOLS.includes("task"), false);
  });

  it("\u672A\u77E5 GetMcpTools \u540D\u79F0\u65F6\u56DE\u9000\u4E3A\u4E0D\u7981\u7528", () => {
    assert.deepEqual(
      fallbackDisallowedTools(new Error("Unknown tool name: GetMcpTools")),
      CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK,
    );
    assert.equal(fallbackDisallowedTools(new Error("invalid model")), null);
  });
});
