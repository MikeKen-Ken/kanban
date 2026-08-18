import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  DISPATCH_SCOPED_TOOL_NAMES,
  formatScopedKanbanToolPrompt,
} from "./dispatch_scoped_tool_prompt.ts";

describe("dispatch_scoped_tool_prompt", () => {
  it("工具名按字母序与门禁对齐", () => {
    assert.deepEqual([...DISPATCH_SCOPED_TOOL_NAMES], [
      "block_card",
      "ready_to_submit",
      "submit_consultation",
    ]);
  });

  it("注入 cardId 并禁止再发现 schema", () => {
    const text = formatScopedKanbanToolPrompt("card-z");
    assert.match(text, /禁止 `GetMcpTools`/);
    assert.match(text, /card-z/);
    assert.match(text, /ready_to_submit/);
    assert.match(text, /CallMcpTool/);
    assert.match(text, /不要与 Shell 并行|禁止把 ready_to_submit 与 Shell/);
  });
});
