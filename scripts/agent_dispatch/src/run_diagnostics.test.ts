import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  AgentRunDiagnostics,
  formatAgentRunDiagnostics,
} from "./run_diagnostics.ts";

describe("run_diagnostics", () => {
  it("统计重复工具与重复文件读取", () => {
    const diagnostics = new AgentRunDiagnostics();
    diagnostics.recordStep({
      type: "toolCall",
      toolName: "read",
      detail: '{"path":"C:\\\\repo\\\\a.dart"}',
    });
    diagnostics.recordStep({
      type: "toolCall",
      toolName: "read",
      detail: '{"path":"C:\\\\repo\\\\a.dart"}',
    });
    diagnostics.recordStep({ type: "thinkingMessage" });

    const metrics = diagnostics.snapshot();
    assert.equal(metrics.steps, 3);
    assert.equal(metrics.toolCalls, 2);
    assert.equal(metrics.repeatedToolCalls, 1);
    assert.equal(metrics.repeatedReads, 1);
    assert.match(formatAgentRunDiagnostics(metrics), /repeatedReads=1/);
  });
});
