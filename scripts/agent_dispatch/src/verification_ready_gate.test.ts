import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  CursorShellSpanEmitter,
  isShellSpanEvent,
  normalizeDispatchCallId,
  toShellSpanReportPayload,
} from "./cursor_shell_spans.ts";
import {
  isVerificationCommand,
  readyBlockedByShells,
  shellEffectiveEndMs,
} from "./verification_ready_gate.ts";

describe("verification_ready_gate", () => {
  it("把 SDK 提前 completed 的 flutter test 当成仍在执行", () => {
    const span = {
      callId: "1",
      command:
        'dart format a.dart; if ($LASTEXITCODE -eq 0) { flutter test "a_test.dart" }',
      startedAtMs: 1_000,
      endedAtMs: 1_331,
      executionTimeMs: 13_639,
      exitCode: 0,
    };
    assert.equal(shellEffectiveEndMs(span), 1_000 + 13_639);
    const blocked = readyBlockedByShells([span], 1_000 + 1_845);
    assert.match(blocked ?? "", /仍在执行/);
    assert.equal(readyBlockedByShells([span], 1_000 + 13_639), undefined);
  });

  it("git 与 dart format 不算验证命令", () => {
    assert.equal(
      readyBlockedByShells(
        [
          {
            callId: "g",
            command: "git status --short",
            startedAtMs: 0,
            endedAtMs: 10,
          },
        ],
        20,
      ),
      undefined,
    );
  });

  it("node --test 与 flutter analyze 算验证命令", () => {
    assert.equal(isVerificationCommand("node --test src/retry.test.ts"), true);
    assert.equal(
      isVerificationCommand("node.exe --test src/retry.test.ts"),
      true,
    );
    assert.equal(isVerificationCommand("flutter analyze"), true);
    const blocked = readyBlockedByShells(
      [
        {
          callId: "n",
          command: "node --test src/retry.test.ts src/run_batch.test.ts",
          startedAtMs: 1_000,
          endedAtMs: 1_200,
          executionTimeMs: 40_000,
          exitCode: 0,
        },
      ],
      1_000 + 5_000,
    );
    assert.match(blocked ?? "", /仍在执行/);
  });
});

describe("CursorShellSpanEmitter", () => {
  it("配对 start/end 并记录 ready_to_submit 时间", () => {
    const emitter = new CursorShellSpanEmitter();
    const start = emitter.observe(
      {
        type: "toolCall",
        message: {
          type: "shell",
          args: { command: "flutter test a_test.dart" },
        },
      },
      1_000,
    );
    assert.equal(start && "phase" in start ? start.phase : "", "start");
    const end = emitter.observe(
      {
        type: "toolCall",
        message: {
          type: "shell",
          args: { command: "flutter test a_test.dart" },
          result: {
            status: "success",
            value: { exitCode: 0, executionTime: 13_639 },
          },
        },
      },
      1_331,
    );
    assert.equal(end && "phase" in end ? end.phase : "", "end");
    emitter.observe(
      {
        type: "toolCall",
        message: {
          type: "mcp",
          args: { toolName: "ready_to_submit" },
        },
      },
      2_845,
    );
    assert.equal(emitter.lastReadyStartedAtMs(), 2_845);
    const span = emitter.snapshot()[0];
    assert.equal(span?.executionTimeMs, 13_639);
    assert.match(
      readyBlockedByShells(emitter.snapshot(), emitter.lastReadyStartedAtMs() ?? 0) ??
        "",
      /仍在执行/,
    );
  });

  it("规范化换行 call_id，并识别 SDK tool 形态", () => {
    assert.equal(normalizeDispatchCallId("call_abc\nfc_xyz"), "call_abc_fc_xyz");
    const emitter = new CursorShellSpanEmitter();
    const start = emitter.observe(
      {
        type: "toolCall",
        call_id: "call_abc\nfc_xyz",
        tool: {
          name: "Shell",
          args: { command: "node --test src/retry.test.ts" },
        },
      },
      1_000,
    );
    assert.equal(isShellSpanEvent(start), true);
    assert.equal(start && "callId" in start ? start.callId : "", "call_abc_fc_xyz");
    const end = emitter.observe(
      {
        type: "toolResult",
        call_id: "call_abc\nfc_xyz",
        tool: {
          name: "Shell",
          result: { value: { exitCode: 0, executionTime: 12_000 } },
        },
      },
      1_400,
    );
    assert.equal(isShellSpanEvent(end), true);
    if (!isShellSpanEvent(end)) throw new Error("expected shell end event");
    const payload = toShellSpanReportPayload({
      workerToken: " worker-a ",
      sessionId: "session-a",
      span: end,
    });
    assert.equal(payload.callId, "call_abc_fc_xyz");
    assert.equal(payload.phase, "end");
    assert.equal(payload.workerToken, "worker-a");
    assert.equal(payload.executionTimeMs, 12_000);
  });

  it("缺 workerToken 时不把空字段打到 MCP", () => {
    assert.throws(
      () =>
        toShellSpanReportPayload({
          workerToken: "  ",
          sessionId: "session-a",
          span: {
            callId: "c1",
            command: "flutter test",
            phase: "start",
            startedAtMs: 1,
          },
        }),
      /workerToken/,
    );
  });

  it("没有 call_id 时用合成 id，避免空字段上报", () => {
    const emitter = new CursorShellSpanEmitter();
    const start = emitter.observe(
      {
        type: "toolCall",
        message: {
          type: "shell",
          args: { command: "flutter analyze" },
        },
      },
      1_000,
    );
    assert.equal(isShellSpanEvent(start), true);
    assert.match(start && "callId" in start ? start.callId : "", /^shell-/);
    const end = emitter.observe(
      {
        type: "toolCall",
        message: {
          type: "shell",
          args: { command: "flutter analyze" },
          result: { value: { exitCode: 0, executionTime: 800 } },
        },
      },
      1_100,
    );
    assert.equal(isShellSpanEvent(end), true);
    assert.equal(end && "callId" in end ? end.callId : "", start && "callId" in start ? start.callId : "");
  });
});
