import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  DISPATCH_SCOPED_TOOL_NAMES,
  formatScopedKanbanToolPrompt,
} from "./dispatch_scoped_tool_prompt.ts";

describe("dispatch_scoped_tool_prompt", () => {
  it("\u5DE5\u5177\u540D\u6309\u5B57\u6BCD\u5E8F\u4E0E\u95E8\u7981\u5BF9\u9F50", () => {
    assert.deepEqual([...DISPATCH_SCOPED_TOOL_NAMES], [
      "block_card",
      "ready_to_submit",
      "submit_consultation",
    ]);
  });

  it("\u6CE8\u5165 cardId \u5E76\u7981\u6B62\u518D\u53D1\u73B0 schema", () => {
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

  it("\u672C\u5361\u5173\u95ED\u6D4B\u8BD5\u65F6\u6CE8\u5165\u8DF3\u8FC7\u81EA\u52A8\u5316\u6D4B\u8BD5\u4E0E\u58F0\u660E\u539F\u56E0", () => {
    const text = formatScopedKanbanToolPrompt("card-z", false);
    assert.match(text, /configured not to require tests/);
    assert.match(text, /manualVerificationReason=This card has no test switch enabled/);
    assert.doesNotMatch(text, /Wait until the test command returns exitCode=0/);
  });
});
