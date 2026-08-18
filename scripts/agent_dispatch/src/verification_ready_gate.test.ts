import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { CursorShellSpanEmitter } from "./cursor_shell_spans.ts";
import {
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
});
