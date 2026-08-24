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
    assert.match(text, /Do not call `GetMcpTools`/);
    assert.match(text, /card-z/);
    assert.match(text, /ready_to_submit/);
    assert.match(text, /CallMcpTool/);
    assert.match(text, /Do not put ready_to_submit in the same parallel tool batch as Shell/);
    assert.match(text, /stop all tools/);
    assert.match(text, /cardKind=consultation/);
    assert.match(text, /working_directory must match relative paths in the command/);
  });

  it("本卡关闭测试时注入跳过自动化测试与声明原因", () => {
    const text = formatScopedKanbanToolPrompt("card-z", false);
    assert.match(text, /configured not to require tests/);
    assert.match(text, /manualVerificationReason=This card has no test switch enabled/);
    assert.doesNotMatch(text, /Wait until the test command returns exitCode=0/);
  });
});
