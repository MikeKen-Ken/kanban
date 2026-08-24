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
  it("把助手回复标成 AI 信息，而不是警告", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: { type: "agent_message", text: "已声明完成，等待 Worker 验证与收尾。" },
    });
    assert.deepEqual(records, [
      {
        line: "Assistant: 已声明完成，等待 Worker 验证与收尾。",
        source: "ai",
        level: "info",
      },
    ]);
  });

  it("Codex 助手 content 块也会打成完整正文", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "agent_message",
        content: [
          { type: "output_text", text: "第一段\n第二段完整结论。" },
        ],
      },
    });
    assert.equal(records[0]?.line, "Assistant: 第一段");
    assert.equal(records[1]?.line, "  │ 第二段完整结论。");
  });

  it("把 reasoning 标成思考", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: { type: "reasoning", text: "先定位玻璃层实现。" },
    });
    assert.equal(records[0]?.source, "ai");
    assert.equal(records[0]?.line, "Thinking: 先定位玻璃层实现。");
  });

  it("思考段落之间的空行不打成只有 │ 的续行", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "reasoning",
        text: "正在处理重修卡片。\n\n发现下拉框仍显示密钥名。",
      },
    });
    assert.deepEqual(
      records.map((record) => record.line),
      ["Thinking: 正在处理重修卡片。", "  │ 发现下拉框仍显示密钥名。"],
    );
  });

  it("命令开始是命令来源；失败才是错误；输出里的 git warning 仍是警告", () => {
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

  it("成功命令不刷完整输出，只抽出诊断行", () => {
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

  it("不把 Dart 命名参数 error: 当成命令诊断", () => {
    const records = recordsFromCodexEvent({
      type: "item.completed",
      item: {
        type: "command_execution",
        command: "Get-Content agent_dispatch_service.dart",
        status: "completed",
        exit_code: 0,
        aggregated_output:
          "error: e,\nerror: '尚未配置 Cursor API Key，请先在 Agent 调度面板中安全保存',\nerror: failed to add",
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

  it("exit_code=0 时不把 Codex status=failed 当成命令失败", () => {
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

  it("rg 无匹配与搜索语法问题不会被标成任务错误", () => {
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

  it("MCP 调用按工具来源记录，失败才升级为错误", () => {
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
        error: { message: "看板未就绪" },
      },
    });
    assert.deepEqual(failed, [
      {
        line: "Tool failed: ready_to_submit 看板未就绪",
        source: "mcp",
        level: "error",
      },
    ]);
  });

  it("apply_patch 完成记录变更路径", () => {
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

  it("回合用量写成会话 token 行", () => {
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

  it("顶层 error 默认是失败，重连提示仍是信息", () => {
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

  it("item.error 是非致命警告", () => {
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
  it("JSON 接通后不再把 TTY 会话回放当警告，只保留诊断行", () => {
    const state = createCodexLogState();
    const jsonRecords = recordsFromCodexJsonLine(
      JSON.stringify({
        type: "item.completed",
        item: { type: "agent_message", text: "完成" },
      }),
      state,
    );
    assert.equal(jsonRecords[0]?.source, "ai");
    assert.equal(state.jsonSeen, true);

    assert.deepEqual(recordsFromCodexStderrLine("codex", state), []);
    assert.deepEqual(
      recordsFromCodexStderrLine("我会只处理这张卡片。", state),
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

  it("没有 JSON 时按 TTY 角色分类，并跳过用户提示正文", () => {
    const state = createCodexLogState();
    assert.deepEqual(recordsFromCodexStderrLine("OpenAI Codex v0.147.0", state), [
      { line: "OpenAI Codex v0.147.0", source: "worker", level: "info" },
    ]);
    assert.deepEqual(recordsFromCodexStderrLine("user", state), []);
    assert.deepEqual(
      recordsFromCodexStderrLine("# Skill 正文", state),
      [],
    );
    assert.deepEqual(
      recordsFromCodexStderrLine('  "error": "看板未就绪"', state),
      [],
    );
    assert.deepEqual(recordsFromCodexStderrLine("codex", state), []);
    assert.deepEqual(recordsFromCodexStderrLine("先定位玻璃层。", state), [
      { line: "Assistant: 先定位玻璃层。", source: "ai", level: "info" },
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

  it("源码里出现 error 字样不会被当成错误", () => {
    const state = createCodexLogState();
    recordsFromCodexStderrLine("exec", state);
    recordsFromCodexStderrLine("rg error", state);
    assert.deepEqual(
      recordsFromCodexStderrLine(
        "app/lib/foo.dart:43:    if (board == null) return mcpErrorResult('看板未就绪');",
        state,
      ),
      [],
    );
  });
});

describe("createLineBuffer", () => {
  it("按行切分并不丢尾块", () => {
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
