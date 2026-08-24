import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { truncateLogOutput } from "./verification_log.ts";
import { describeMissingExecutable } from "./verification_runner.ts";

describe("verification_log", () => {
  it("truncates long validation output while preserving the beginning", () => {
    const output = "a".repeat(5000);
    const truncated = truncateLogOutput(output);
    assert.equal(truncated.startsWith("a".repeat(4000)), true);
    assert.match(truncated, /log truncated/);
  });
});

describe("describeMissingExecutable", () => {
  it("identifies ENOENT and the Kanban process PATH", () => {
    assert.match(describeMissingExecutable("flutter"), /Executable flutter was not found/);
    assert.match(describeMissingExecutable("flutter"), /ENOENT/);
    assert.match(describeMissingExecutable("flutter"), /Kanban process PATH/);
  });
});
