import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  dispatchTerminalFromSession,
  dispatchTerminalToolName,
  isSuccessfulDispatchTerminalStep,
  startPollingDispatchTerminal,
} from "./dispatch_terminal.ts";

describe("dispatch_terminal", () => {
  it("\u5F00\u59CB\u8C03\u7528 ready_to_submit \u4E0D\u7B97\u6210\u529F", () => {
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

  it("MCP \u6210\u529F\u7ED3\u679C\u624D\u7ED3\u675F\u4F1A\u8BDD", () => {
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

  it("pending.declared \u4F18\u5148\u4E8E\u5361\u7247\u5217", () => {
    assert.equal(
      dispatchTerminalFromSession({ pending: { status: "declared" } }),
      "declared",
    );
    assert.equal(
      dispatchTerminalFromSession({}, { columnName: "\u5F85\u9A8C\u8BC1" }),
      "verify",
    );
    assert.equal(
      dispatchTerminalFromSession({}, { columnId: "blocked" }),
      "blocked",
    );
    assert.equal(
      dispatchTerminalFromSession({}, { columnName: "\u8FDB\u884C\u4E2D" }),
      "none",
    );
  });

  it("peek \u5230 declared \u540E\u505C\u6B62\u8F6E\u8BE2", async () => {
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
