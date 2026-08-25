import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  CURSOR_WORKER_DISALLOWED_TOOLS,
  CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK,
  fallbackDisallowedTools,
} from "./cursor_disallowed_tools.ts";

describe("cursor_disallowed_tools", () => {
  it("\u4FDD\u7559 MCP \u76EE\u5F55\u53D1\u73B0，\u53EA\u7981\u7528\u65E0\u5934 askQuestion", () => {
    assert.deepEqual(CURSOR_WORKER_DISALLOWED_TOOLS, ["askQuestion"]);
    assert.equal(CURSOR_WORKER_DISALLOWED_TOOLS.includes("GetMcpTools"), false);
    assert.equal(CURSOR_WORKER_DISALLOWED_TOOLS.includes("task"), false);
  });

  it("SDK \u4E0D\u8BC6\u522B askQuestion \u540D\u79F0\u65F6\u56DE\u9000\u4E3A\u4E0D\u7981\u7528", () => {
    assert.deepEqual(
      fallbackDisallowedTools(new Error("Unknown tool name: askQuestion")),
      CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK,
    );
    assert.equal(fallbackDisallowedTools(new Error("invalid model")), null);
  });
});
