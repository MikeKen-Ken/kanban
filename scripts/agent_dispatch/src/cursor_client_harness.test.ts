import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { CURSOR_CLIENT_SETTING_SOURCES } from "./run_cursor.ts";

describe("Cursor client harness", () => {
  it("loads the complete Cursor client settings stack", () => {
    assert.deepEqual(CURSOR_CLIENT_SETTING_SOURCES, ["all"]);
  });
});
