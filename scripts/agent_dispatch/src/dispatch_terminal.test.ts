import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  dispatchTerminalFromSession,
  dispatchTerminalToolName,
  isSuccessfulDispatchTerminalStep,
  startPollingDispatchTerminal,
} from "./dispatch_terminal.ts";

describe("dispatch_terminal", () => {
  it("开始调用 ready_to_submit 不算成功", () => {
    const start = {
      type: "toolCall",
      message: {
        type: "mcp",
        args: { toolName: "ready_to_submit" },
      },
    };
    assert.equal(dispatchTerminalToolName(start), "ready_to_submit");
    assert.equal(isSuccessfulDispatchTerminalStep(start), false);
  });

  it("MCP 成功结果才结束会话", () => {
    assert.equal(
      isSuccessfulDispatchTerminalStep({
        type: "toolCall",
        message: {
          type: "mcp",
          args: { toolName: "ready_to_submit" },
          result: { status: "success", value: { ok: true } },
        },
      }),
      true,
    );
    assert.equal(
      isSuccessfulDispatchTerminalStep({
        type: "toolCall",
        message: {
          type: "mcp",
          args: { toolName: "ready_to_submit" },
          result: { status: "error", isError: true },
        },
      }),
      false,
    );
  });

  it("pending.declared 优先于卡片列", () => {
    assert.equal(
      dispatchTerminalFromSession({ pending: { status: "declared" } }),
      "declared",
    );
    assert.equal(
      dispatchTerminalFromSession({}, { columnName: "待验证" }),
      "verify",
    );
    assert.equal(
      dispatchTerminalFromSession({}, { columnId: "blocked" }),
      "blocked",
    );
    assert.equal(
      dispatchTerminalFromSession({}, { columnName: "进行中" }),
      "none",
    );
  });

  it("peek 到 declared 后停止轮询", async () => {
    let calls = 0;
    const seen: string[] = [];
    const poll = startPollingDispatchTerminal(
      async () => {
        calls += 1;
        return calls >= 2 ? "declared" : "none";
      },
      (kind) => seen.push(kind),
      10,
    );
    await new Promise((resolve) => setTimeout(resolve, 80));
    poll.stop();
    assert.deepEqual(seen, ["declared"]);
    assert.ok(calls >= 2);
  });
});
