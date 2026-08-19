import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  extractAssistantText,
  extractCodexAssistantEventText,
  extractCodexTranscriptMessage,
  extractConversationMessages,
  extractCursorAssistantStepText,
} from "./assistant_text.ts";

describe("assistant_text", () => {
  it("抽出 Cursor 助手步骤的正文，包括 content 块", () => {
    assert.equal(
      extractCursorAssistantStepText({
        type: "assistantMessage",
        message: { text: "短句" },
      }),
      "短句",
    );
    assert.equal(
      extractCursorAssistantStepText({
        type: "assistantMessage",
        message: {
          content: [
            { type: "text", text: "第一段\n" },
            { type: "output_text", text: "完整结论。" },
          ],
        },
      }),
      "第一段\n完整结论。",
    );
    assert.equal(
      extractCursorAssistantStepText({ type: "toolCall", message: { text: "x" } }),
      "",
    );
  });

  it("抽出 Codex 已完成的助手条目，忽略工具与未完成项", () => {
    assert.equal(
      extractCodexAssistantEventText({
        type: "item.completed",
        item: {
          type: "agent_message",
          content: [{ type: "output_text", text: "已改完对话落盘。" }],
        },
      }),
      "已改完对话落盘。",
    );
    assert.equal(
      extractCodexAssistantEventText({
        type: "item.updated",
        item: { type: "agent_message", text: "流式中" },
      }),
      "",
    );
    assert.equal(extractAssistantText({ text: "  明文  " }), "明文");
    assert.deepEqual(
      extractCodexTranscriptMessage({
        type: "item.completed",
        item: { type: "user_message", text: "用方案 A" },
      }),
      { role: "user", text: "用方案 A" },
    );
  });

  it("从 Cursor 会话回合抽出用户与全部助手消息", () => {
    assert.deepEqual(
      extractConversationMessages([
        {
          type: "agentConversationTurn",
          turn: {
            userMessage: { text: "请继续" },
            steps: [
              { type: "thinkingMessage", message: { text: "内部思考" } },
              {
                type: "assistantMessage",
                message: { text: "第一条助手。" },
              },
              { type: "toolCall", message: { type: "read", args: {} } },
              {
                type: "assistantMessage",
                message: { text: "第二条助手。" },
              },
            ],
          },
        },
      ]),
      [
        { role: "user", text: "请继续" },
        { role: "assistant", text: "第一条助手。" },
        { role: "assistant", text: "第二条助手。" },
      ],
    );
  });
});
