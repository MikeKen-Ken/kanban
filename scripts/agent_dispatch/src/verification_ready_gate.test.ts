import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  CursorShellSpanEmitter,
  isShellSpanEvent,
  normalizeDispatchCallId,
  toShellSpanReportPayload,
} from "./cursor_shell_spans.ts";
import {
  isUneexecutedCdAndVerification,
  isVerificationCommand,
  readyBlockedByShells,
  shellEffectiveEndMs,
  shellObservedDurationMs,
} from "./verification_ready_gate.ts";

describe("verification_ready_gate", () => {
  it("\u628A SDK \u63D0\u524D completed \u7684 flutter test \u5F53\u6210\u4ECD\u5728\u6267\u884C", () => {
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
    assert.match(blocked ?? "", /still running/);
    assert.equal(readyBlockedByShells([span], 1_000 + 13_639), undefined);
  });

  it("git \u4E0E dart format \u4E0D\u7B97\u9A8C\u8BC1\u547D\u4EE4", () => {
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

  it("\u6EDE\u540E\u4E0A\u62A5\u7684 cd && \u89E3\u6790\u5931\u8D25\u4E0D\u5F97\u8986\u76D6\u5DF2\u901A\u8FC7\u7684\u6D4B\u8BD5", () => {
    const passed = {
      callId: "pass",
      command: "flutter test test/a_test.dart",
      startedAtMs: 1_000,
      endedAtMs: 21_000,
      executionTimeMs: 20_000,
      exitCode: 0,
    };
    const parseFail = {
      callId: "cd-and",
      command: "cd app && flutter test test/a_test.dart",
      startedAtMs: 900,
      endedAtMs: 50_000,
      executionTimeMs: 80,
      exitCode: 1,
    };
    assert.equal(shellEffectiveEndMs(parseFail), 900 + 80);
    assert.equal(isUneexecutedCdAndVerification(parseFail), true);
    assert.equal(readyBlockedByShells([passed, parseFail], 50_000), undefined);
  });

  it("\u4EC5\u6709 cd && \u77ED\u5931\u8D25\u65F6\u4ECD\u62D2\u7EDD", () => {
    const blocked = readyBlockedByShells(
      [
        {
          callId: "cd-and",
          command: "cd app && flutter test test/a_test.dart",
          startedAtMs: 0,
          endedAtMs: 100,
          executionTimeMs: 80,
          exitCode: 1,
        },
      ],
      1_000,
    );
    assert.match(blocked ?? "", /working_directory/);
  });

  it("flutter test \u6210\u529F\u4F46\u8017\u65F6\u8FC7\u77ED\u65F6\u62D2\u7EDD", () => {
    const blocked = readyBlockedByShells(
      [
        {
          callId: "fast",
          command:
            "dart format a.dart; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; flutter test a_test.dart",
          startedAtMs: 0,
          endedAtMs: 600,
          executionTimeMs: 600,
          exitCode: 0,
        },
      ],
      1_000,
    );
    assert.match(blocked ?? "", /implausibly quickly/);
  });

  it("\u65E0 executionTime \u7684\u79D2\u9000 flutter test \u4E5F\u62D2\u7EDD", () => {
    const span = {
      callId: "fast",
      command: "flutter test test/a_test.dart",
      startedAtMs: 0,
      endedAtMs: 600,
      exitCode: 0,
    };
    assert.equal(shellObservedDurationMs(span), 600);
    const blocked = readyBlockedByShells([span], 1_000);
    assert.match(blocked ?? "", /working_directory/);
  });

  it("\u6B63\u5E38\u8017\u65F6\u7684 flutter test \u4ECD\u653E\u884C", () => {
    assert.equal(
      readyBlockedByShells(
        [
          {
            callId: "ok",
            command: "flutter test test/a_test.dart",
            startedAtMs: 0,
            endedAtMs: 8_000,
            executionTimeMs: 8_000,
            exitCode: 0,
          },
        ],
        9_000,
      ),
      undefined,
    );
  });

  it("node --test \u4E0E flutter analyze \u7B97\u9A8C\u8BC1\u547D\u4EE4", () => {
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
    assert.match(blocked ?? "", /still running/);
  });
});

describe("CursorShellSpanEmitter", () => {
  it("\u914D\u5BF9 start/end \u5E76\u8BB0\u5F55 ready_to_submit \u65F6\u95F4", () => {
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
      /still running/,
    );
  });

  it("\u89C4\u8303\u5316\u6362\u884C call_id，\u5E76\u8BC6\u522B SDK tool \u5F62\u6001", () => {
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

  it("\u7F3A workerToken \u65F6\u4E0D\u628A\u7A7A\u5B57\u6BB5\u6253\u5230 MCP", () => {
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

  it("\u6CA1\u6709 call_id \u65F6\u7528\u5408\u6210 id，\u907F\u514D\u7A7A\u5B57\u6BB5\u4E0A\u62A5", () => {
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
