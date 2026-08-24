import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  extractAssistantText,
  extractCodexAssistantEventText,
  extractCodexTranscriptMessage,
  extractConversationMessages,
  extractCursorAssistantStepText,
  extractCursorThinkingStepText,
} from "./assistant_text.ts";

describe("assistant_text", () => {
  it("\u62BD\u51FA Cursor \u52A9\u624B\u6B65\u9AA4\u7684\u6B63\u6587，\u5305\u62EC content \u5757", () => {
    assert.equal(
      extractCursorAssistantStepText({
        type: "assistantMessage",
        message: { text: "\u77ED\u53E5" },
      }),
      "\u77ED\u53E5",
    );
    assert.equal(
      extractCursorAssistantStepText({
        type: "assistantMessage",
        message: {
          content: [
            { type: "text", text: "\u7B2C\u4E00\u6BB5\n" },
            { type: "output_text", text: "\u5B8C\u6574\u7ED3\u8BBA。" },
          ],
        },
      }),
      "\u7B2C\u4E00\u6BB5\n\u5B8C\u6574\u7ED3\u8BBA。",
    );
    assert.equal(
      extractCursorAssistantStepText({ type: "toolCall", message: { text: "x" } }),
      "",
    );
  });

  it("\u62BD\u51FA Codex \u5DF2\u5B8C\u6210\u7684\u52A9\u624B\u6761\u76EE，\u5FFD\u7565\u5DE5\u5177\u4E0E\u672A\u5B8C\u6210\u9879", () => {
    assert.equal(
      extractCodexAssistantEventText({
        type: "item.completed",
        item: {
          type: "agent_message",
          content: [{ type: "output_text", text: "\u5DF2\u6539\u5B8C\u5BF9\u8BDD\u843D\u76D8。" }],
        },
      }),
      "\u5DF2\u6539\u5B8C\u5BF9\u8BDD\u843D\u76D8。",
    );
    assert.equal(
      extractCodexAssistantEventText({
        type: "item.updated",
        item: { type: "agent_message", text: "\u6D41\u5F0F\u4E2D" },
      }),
      "",
    );
    assert.equal(extractAssistantText({ text: "  \u660E\u6587  " }), "\u660E\u6587");
    assert.deepEqual(
      extractCodexTranscriptMessage({
        type: "item.completed",
        item: { type: "user_message", text: "\u7528\u65B9\u6848 A" },
      }),
      { role: "user", text: "\u7528\u65B9\u6848 A" },
    );
  });

  it("\u4ECE Cursor \u4F1A\u8BDD\u56DE\u5408\u62BD\u51FA\u601D\u8003\u4E0E\u5168\u90E8\u52A9\u624B\u6D88\u606F", () => {
    assert.deepEqual(
      extractConversationMessages([
        {
          type: "agentConversationTurn",
          turn: {
            userMessage: { text: "\u8BF7\u7EE7\u7EED" },
            steps: [
              { type: "thinkingMessage", message: { text: "\u5185\u90E8\u601D\u8003" } },
              { type: "thinking", text: "\u7B2C\u4E8C\u6BB5\u601D\u8003\u6B65\u9AA4" },
              {
                type: "assistantMessage",
                message: { text: "\u7B2C\u4E00\u6761\u52A9\u624B。" },
              },
              { type: "toolCall", message: { type: "read", args: {} } },
              {
                type: "assistantMessage",
                message: { text: "\u7B2C\u4E8C\u6761\u52A9\u624B。" },
              },
            ],
          },
        },
      ]),
      [
        { role: "user", text: "\u8BF7\u7EE7\u7EED" },
        { role: "thinking", text: "\u5185\u90E8\u601D\u8003" },
        { role: "thinking", text: "\u7B2C\u4E8C\u6BB5\u601D\u8003\u6B65\u9AA4" },
        { role: "assistant", text: "\u7B2C\u4E00\u6761\u52A9\u624B。" },
        { role: "assistant", text: "\u7B2C\u4E8C\u6761\u52A9\u624B。" },
      ],
    );
  });

  it("\u62BD\u51FA Codex \u5DF2\u5B8C\u6210\u7684\u601D\u8003\u6761\u76EE", () => {
    assert.deepEqual(
      extractCodexTranscriptMessage({
        type: "item.completed",
        item: { type: "reasoning", text: "\u5148\u6838\u5BF9\u843D\u76D8\u5B57\u6BB5。" },
      }),
      { role: "thinking", text: "\u5148\u6838\u5BF9\u843D\u76D8\u5B57\u6BB5。" },
    );
    assert.deepEqual(
      extractCodexTranscriptMessage({
        type: "item.updated",
        item: {
          type: "reasoning",
          content: [{ type: "reasoning_text", text: "\u6D41\u5F0F\u601D\u8003\u6B65\u9AA4。" }],
        },
      }),
      { role: "thinking", text: "\u6D41\u5F0F\u601D\u8003\u6B65\u9AA4。" },
    );
  });

  it("\u62BD\u51FA Cursor SDK thinking \u6D88\u606F\u4E0E\u5E26 thinkingDurationMs \u7684\u6B65\u9AA4", () => {
    assert.equal(
      extractCursorThinkingStepText({
        type: "thinking",
        text: "SDK \u601D\u8003\u6B65\u9AA4",
      }),
      "SDK \u601D\u8003\u6B65\u9AA4",
    );
    assert.equal(
      extractCursorThinkingStepText({
        type: "unknownStep",
        message: { thinking: "\u5D4C\u5957\u601D\u8003", thinkingDurationMs: 12 },
      }),
      "\u5D4C\u5957\u601D\u8003",
    );
  });
});
