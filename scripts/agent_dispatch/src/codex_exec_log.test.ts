import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  createCodexLogState,
  createLineBuffer,
  recordsFromCodexEvent,
  recordsFromCodexJsonLine,
  recordsFromCodexStderrLine,
} from "./codex_exec_log.ts";

describe("recordsFromCodexEvent", () => {
  it("marks assistant replies as AI information rather than warnings", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "agent_message",
        text: "Completion declared; awaiting Worker validation and finalization.",
      },
    });
    assert.deepEqual(records, [
      {
        line: "Assistant: Completion declared; awaiting Worker validation and finalization.",
        source: "ai",
        level: "info",
      },
    ]);
  });

  it("Codex \u52A9\u624B content \u5757\u4E5F\u4F1A\u6253\u6210\u5B8C\u6574\u6B63\u6587", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "agent_message",
        content: [
          { type: "output_text", text: "\u7B2C\u4E00\u6BB5\n\u7B2C\u4E8C\u6BB5\u5B8C\u6574\u7ED3\u8BBA。" },
        ],
      },
    });
    assert.equal(records[0]?.line, "Assistant: \u7B2C\u4E00\u6BB5");
    assert.equal(records[1]?.line, "  │ \u7B2C\u4E8C\u6BB5\u5B8C\u6574\u7ED3\u8BBA。");
  });

  it("\u628A reasoning \u6807\u6210\u601D\u8003", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: { type: "reasoning", text: "\u5148\u5B9A\u4F4D\u73BB\u7483\u5C42\u5B9E\u73B0。" },
    });
    assert.equal(records[0]?.source, "ai");
    assert.equal(records[0]?.line, "Thinking: \u5148\u5B9A\u4F4D\u73BB\u7483\u5C42\u5B9E\u73B0。");
  });

  it("\u601D\u8003\u6BB5\u843D\u4E4B\u95F4\u7684\u7A7A\u884C\u4E0D\u6253\u6210\u53EA\u6709 │ \u7684\u7EED\u884C", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "reasoning",
        text: "\u6B63\u5728\u5904\u7406\u91CD\u4FEE\u5361\u7247。\n\n\u53D1\u73B0\u4E0B\u62C9\u6846\u4ECD\u663E\u793A\u5BC6\u94A5\u540D。",
      },
    });
    assert.deepEqual(
      records.map((record) => record.line),
      ["Thinking: \u6B63\u5728\u5904\u7406\u91CD\u4FEE\u5361\u7247。", "  │ \u53D1\u73B0\u4E0B\u62C9\u6846\u4ECD\u663E\u793A\u5BC6\u94A5\u540D。"],
    );
  });

  it("\u547D\u4EE4\u5F00\u59CB\u662F\u547D\u4EE4\u6765\u6E90；\u5931\u8D25\u624D\u662F\u9519\u8BEF；\u8F93\u51FA\u91CC\u7684 git warning \u4ECD\u662F\u8B66\u544A", () => {
    const started = recordsFromCodexEvent({
      type: "item.started",
      item: {
        type: "command_execution",
        command: "git add app/lib/foo.dart",
        status: "in_progress",
      },
    });
    assert.deepEqual(started, [
      { line: "Command: git add app/lib/foo.dart", source: "shell", level: "info" },
    ]);

    const failed = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "command_execution",
        command: "git add app/lib/foo.dart",
        status: "failed",
        exit_code: 1,
        aggregated_output:
          "warning: in the working copy of 'foo.dart', LF will be replaced by CRLF\nerror: failed to add",
      },
    });
    assert.equal(failed[0]?.level, "error");
    assert.equal(failed[0]?.source, "shell");
    assert.ok(failed.some((record) => record.level === "warning"));
    assert.ok(failed.some((record) => record.level === "error" && record.line.includes("error: failed")));
  });

  it("\u6210\u529F\u547D\u4EE4\u4E0D\u5237\u5B8C\u6574\u8F93\u51FA，\u53EA\u62BD\u51FA\u8BCA\u65AD\u884C", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "command_execution",
        command: "git status",
        status: "completed",
        exit_code: 0,
        aggregated_output:
          "import 'dart:ui';\nwarning: in the working copy of 'foo.dart', LF will be replaced by CRLF\nclass Foo {}",
      },
    });
    assert.deepEqual(records, [
      {
        line: "warning: in the working copy of 'foo.dart', LF will be replaced by CRLF",
        source: "shell",
        level: "warning",
      },
    ]);
  });

  it("\u4E0D\u628A Dart \u547D\u540D\u53C2\u6570 error: \u5F53\u6210\u547D\u4EE4\u8BCA\u65AD", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "command_execution",
        command: "Get-Content agent_dispatch_service.dart",
        status: "completed",
        exit_code: 0,
        aggregated_output:
          "error: e,\nerror: '\u5C1A\u672A\u914D\u7F6E Cursor API Key，\u8BF7\u5148\u5728 Agent \u8C03\u5EA6\u9762\u677F\u4E2D\u5B89\u5168\u4FDD\u5B58',\nerror: failed to add",
      },
    });
    assert.deepEqual(
      records.filter((record) => record.level === "error"),
      [
        {
          line: "error: failed to add",
          source: "shell",
          level: "error",
        },
      ],
    );
  });

  it("exit_code=0 \u65F6\u4E0D\u628A Codex status=failed \u5F53\u6210\u547D\u4EE4\u5931\u8D25", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "command_execution",
        command: "rg Agent app",
        status: "failed",
        exit_code: 0,
        aggregated_output: "app/lib/main.dart:1: Agent",
      },
    });
    assert.equal(
      records.some((record) => record.line.startsWith("Command failed: ")),
      false,
    );
  });

  it("rg \u65E0\u5339\u914D\u4E0E\u641C\u7D22\u8BED\u6CD5\u95EE\u9898\u4E0D\u4F1A\u88AB\u6807\u6210\u4EFB\u52A1\u9519\u8BEF", () => {
    const noMatch = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "command_execution",
        command: "rg --fixed-strings -- title app/src",
        status: "failed",
        exit_code: 1,
      },
    });
    assert.deepEqual(noMatch, [
      {
        line: "Search had no matches: rg --fixed-strings -- title app/src",
        source: "shell",
        level: "info",
      },
    ]);

    const badSearch = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "command_execution",
        command: "rg \"(unclosed\" app/src",
        status: "failed",
        exit_code: 2,
        aggregated_output: "rg: regex parse error: unclosed group",
      },
    });
    assert.equal(badSearch[0]?.level, "warning");
    assert.match(badSearch[0]?.line ?? "", /Search command issue/);
    assert.equal(badSearch.some((record) => record.level === "error"), false);
  });

  it("MCP \u8C03\u7528\u6309\u5DE5\u5177\u6765\u6E90\u8BB0\u5F55，\u5931\u8D25\u624D\u5347\u7EA7\u4E3A\u9519\u8BEF", () => {
    const started = recordsFromCodexEvent({
      type: "item.started",
      item: {
        type: "mcp_tool_call",
        server: "kanbanMCP",
        tool: "ready_to_submit",
        arguments: { cardId: "abc" },
        status: "in_progress",
      },
    });
    assert.equal(started[0]?.source, "mcp");
    assert.match(started[0]?.line ?? "", /^Tool: ready_to_submit /);
    assert.equal(started[0]?.level, "info");

    const failed = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "mcp_tool_call",
        tool: "ready_to_submit",
        status: "failed",
        error: { message: "\u770B\u677F\u672A\u5C31\u7EEA" },
      },
    });
    assert.deepEqual(failed, [
      {
        line: "Tool failed: ready_to_submit \u770B\u677F\u672A\u5C31\u7EEA",
        source: "mcp",
        level: "error",
      },
    ]);
  });

  it("apply_patch \u5B8C\u6210\u8BB0\u5F55\u53D8\u66F4\u8DEF\u5F84", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "file_change",
        status: "completed",
        changes: [
          { path: "app/lib/a.dart", kind: "update" },
          { path: "app/lib/b.dart", kind: "add" },
        ],
      },
    });
    assert.deepEqual(records, [
      {
        line: "Tool: apply_patch updated app/lib/a.dart; added app/lib/b.dart",
        source: "mcp",
        level: "info",
      },
    ]);
  });

  it("\u56DE\u5408\u7528\u91CF\u5199\u6210\u4F1A\u8BDD token \u884C", () => {
    const records = recordsFromCodexEvent({
      type: "turn.completed",
      usage: {
        input_tokens: 24763,
        cached_input_tokens: 24448,
        output_tokens: 122,
      },
    });
    assert.equal(records.length, 1);
    assert.equal(records[0]?.source, "worker");
    assert.match(records[0]?.line ?? "", /^session tokens:/);
    assert.match(records[0]?.line ?? "", /total=/);
  });

  it("\u9876\u5C42 error \u9ED8\u8BA4\u662F\u5931\u8D25，\u91CD\u8FDE\u63D0\u793A\u4ECD\u662F\u4FE1\u606F", () => {
    const fatal = recordsFromCodexEvent({
      type: "error",
      message: "stream error: broken pipe",
    });
    assert.deepEqual(fatal, [
      { line: "stream error: broken pipe", source: "worker", level: "error" },
    ]);

    const reconnect = recordsFromCodexEvent({
      type: "error",
      message: "Reconnecting... 1/5",
    });
    assert.deepEqual(reconnect, [
      { line: "Reconnecting... 1/5", source: "worker", level: "info" },
    ]);
  });

  it("item.error \u662F\u975E\u81F4\u547D\u8B66\u544A", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: { type: "error", message: "command output truncated" },
    });
    assert.deepEqual(records, [
      {
        line: "command output truncated",
        source: "worker",
        level: "warning",
      },
    ]);
  });
});

describe("recordsFromCodexJsonLine / stderr", () => {
  it("JSON \u63A5\u901A\u540E\u4E0D\u518D\u628A TTY \u4F1A\u8BDD\u56DE\u653E\u5F53\u8B66\u544A，\u53EA\u4FDD\u7559\u8BCA\u65AD\u884C", () => {
    const state = createCodexLogState();
    const jsonRecords = recordsFromCodexJsonLine(
      JSON.stringify({
        type: "item.completed",
        item: { type: "agent_message", text: "\u5B8C\u6210" },
      }),
      state,
    );
    assert.equal(jsonRecords[0]?.source, "ai");
    assert.equal(state.jsonSeen, true);

    assert.deepEqual(recordsFromCodexStderrLine("codex", state), []);
    assert.deepEqual(
      recordsFromCodexStderrLine("\u6211\u4F1A\u53EA\u5904\u7406\u8FD9\u5F20\u5361\u7247。", state),
      [],
    );
    assert.deepEqual(
      recordsFromCodexStderrLine(
        "warning: in the working copy of 'foo.dart', LF will be replaced by CRLF",
        state,
      ),
      [
        {
          line: "warning: in the working copy of 'foo.dart', LF will be replaced by CRLF",
          source: "worker",
          level: "warning",
        },
      ],
    );
  });

  it("\u6CA1\u6709 JSON \u65F6\u6309 TTY \u89D2\u8272\u5206\u7C7B，\u5E76\u8DF3\u8FC7\u7528\u6237\u63D0\u793A\u6B63\u6587", () => {
    const state = createCodexLogState();
    assert.deepEqual(recordsFromCodexStderrLine("OpenAI Codex v0.147.0", state), [
      { line: "OpenAI Codex v0.147.0", source: "worker", level: "info" },
    ]);
    assert.deepEqual(recordsFromCodexStderrLine("user", state), []);
    assert.deepEqual(
      recordsFromCodexStderrLine("# Skill \u6B63\u6587", state),
      [],
    );
    assert.deepEqual(
      recordsFromCodexStderrLine('  "error": "\u770B\u677F\u672A\u5C31\u7EEA"', state),
      [],
    );
    assert.deepEqual(recordsFromCodexStderrLine("codex", state), []);
    assert.deepEqual(recordsFromCodexStderrLine("\u5148\u5B9A\u4F4D\u73BB\u7483\u5C42。", state), [
      { line: "Assistant: \u5148\u5B9A\u4F4D\u73BB\u7483\u5C42。", source: "ai", level: "info" },
    ]);
    assert.deepEqual(recordsFromCodexStderrLine("exec", state), []);
    assert.deepEqual(
      recordsFromCodexStderrLine("git status --short", state),
      [{ line: "Command: git status --short", source: "shell", level: "info" }],
    );
    assert.deepEqual(
      recordsFromCodexStderrLine(
        "warning: in the working copy of 'foo.dart', LF will be replaced by CRLF",
        state,
      ),
      [
        {
          line: "warning: in the working copy of 'foo.dart', LF will be replaced by CRLF",
          source: "shell",
          level: "warning",
        },
      ],
    );
    assert.deepEqual(
      recordsFromCodexStderrLine("mcp: kanbanMCP/ready_to_submit started", state),
      [{ line: "Tool: ready_to_submit started", source: "mcp", level: "info" }],
    );
  });

  it("\u6E90\u7801\u91CC\u51FA\u73B0 error \u5B57\u6837\u4E0D\u4F1A\u88AB\u5F53\u6210\u9519\u8BEF", () => {
    const state = createCodexLogState();
    recordsFromCodexStderrLine("exec", state);
    recordsFromCodexStderrLine("rg error", state);
    assert.deepEqual(
      recordsFromCodexStderrLine(
        "app/lib/foo.dart:43:    if (board == null) return mcpErrorResult('\u770B\u677F\u672A\u5C31\u7EEA');",
        state,
      ),
      [],
    );
  });
});

describe("createLineBuffer", () => {
  it("\u6309\u884C\u5207\u5206\u5E76\u4E0D\u4E22\u5C3E\u5757", () => {
    const lines: string[] = [];
    const buffer = createLineBuffer((line) => lines.push(line));
    buffer.push('{"type":"turn.started"}\n{"type":"turn.completed"}');
    buffer.push("\npartial");
    buffer.flush();
    assert.deepEqual(lines, [
      '{"type":"turn.started"}',
      '{"type":"turn.completed"}',
      "partial",
    ]);
  });
});
