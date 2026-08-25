import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { DISPATCH_SCOPED_TOOL_NAMES } from "./dispatch_scoped_tools.ts";

describe("dispatch_scoped_tools", () => {
  it("matches the four scoped tools in alphabetical order", () => {
    assert.deepEqual([...DISPATCH_SCOPED_TOOL_NAMES], [
      "block_card",
      "get_current_card",
      "ready_to_submit",
      "submit_consultation",
    ]);
  });
});
