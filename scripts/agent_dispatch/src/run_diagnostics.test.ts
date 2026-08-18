import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  AgentRunDiagnostics,
  formatAgentRunDiagnostics,
} from "./run_diagnostics.ts";

describe("run_diagnostics", () => {
  it("统计重复工具与重复文件读取", () => {
    const diagnostics = new AgentRunDiagnostics({ maxSteps: 10, maxToolCalls: 8 });
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

  it("超过步骤或工具预算时返回原因", () => {
    const diagnostics = new AgentRunDiagnostics({ maxSteps: 2, maxToolCalls: 1 });
    assert.equal(diagnostics.recordStep({ type: "thinkingMessage" }), undefined);
    assert.equal(
      diagnostics.recordStep({ type: "toolCall", toolName: "grep", detail: "x" }),
      undefined,
    );
    assert.match(
      diagnostics.recordStep({ type: "toolCall", toolName: "grep", detail: "y" }) ?? "",
      /步骤数超过上限/,
    );
  });
});
