import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildConversationTranscript } from "./conversation_transcript.ts";

describe("conversation_transcript", () => {
  it("strips English Worker-injected prompt blobs", () => {
    const messages = buildConversationTranscript({
      sessionUser: "- title",
      fromTurns: [
        {
          role: "user",
          text: "# Skill body\nfull prompt",
        },
        { role: "assistant", text: "Locate the write path first." },
      ],
    });
    assert.deepEqual(messages, [
      { role: "user", text: "- title" },
      { role: "assistant", text: "Locate the write path first." },
    ]);
  });

  it("\u4FDD\u7559\u4F1A\u8BDD\u7528\u6237\u6D88\u606F，\u5E76\u5199\u5165\u6BCF\u4E00\u6761\u52A9\u624B\u6B63\u6587", () => {
    const messages = buildConversationTranscript({
      sessionUser: "- \u6807\u9898\n- \u63CF\u8FF0",
      fromTurns: [
        {
          role: "user",
          text: "# Worker \u6CE8\u5165\u7684\u672C\u8F6E\u4E0A\u4E0B\u6587\n\u5B8C\u6574 prompt",
        },
        { role: "assistant", text: "\u5148\u5B9A\u4F4D\u5199\u5165\u903B\u8F91。" },
        { role: "assistant", text: "\u518D\u8865\u5168\u6240\u6709\u52A9\u624B\u6D88\u606F。" },
      ],
    });
    assert.deepEqual(messages, [
      { role: "user", text: "- \u6807\u9898\n- \u63CF\u8FF0" },
      { role: "assistant", text: "\u5148\u5B9A\u4F4D\u5199\u5165\u903B\u8F91。" },
      { role: "assistant", text: "\u518D\u8865\u5168\u6240\u6709\u52A9\u624B\u6D88\u606F。" },
    ]);
  });

  it("\u5FEB\u7167\u7F3A\u52A9\u624B\u65F6\u56DE\u9000\u5230\u5B9E\u65F6\u8BB0\u5F55，\u5E76\u4FDD\u7559\u8FFD\u95EE\u7528\u6237\u6D88\u606F", () => {
    const messages = buildConversationTranscript({
      sessionUser: "- \u4EFB\u52A1",
      live: [
        { role: "user", text: "- \u4EFB\u52A1" },
        { role: "assistant", text: "\u8BF7\u786E\u8BA4\u65B9\u6848" },
        { role: "user", text: "\u7528\u65B9\u6848 A" },
        { role: "assistant", text: "\u5F00\u59CB\u6539。" },
      ],
      fromTurns: [
        {
          role: "user",
          text: "KANBAN_WORKER_USER_RULES_BEGIN",
        },
      ],
    });
    assert.deepEqual(
      messages.map((item) => `${item.role}:${item.text}`),
      ["user:- \u4EFB\u52A1", "assistant:\u8BF7\u786E\u8BA4\u65B9\u6848", "user:\u7528\u65B9\u6848 A", "assistant:\u5F00\u59CB\u6539。"],
    );
  });

  it("\u7528\u66F4\u957F\u7684\u4F1A\u8BDD\u5FEB\u7167\u5347\u7EA7\u540C\u4E00\u6761\u6D41\u5F0F\u52A9\u624B\u6D88\u606F", () => {
    const messages = buildConversationTranscript({
      sessionUser: "\u5F00\u59CB",
      live: [{ role: "assistant", text: "\u5148\u6539\u4FDD\u5B58。" }],
      fromTurns: [
        { role: "assistant", text: "\u5148\u6539\u4FDD\u5B58。\u518D\u5199\u51FA\u5B8C\u6574\u52A9\u624B\u6B63\u6587。" },
      ],
      trailingAssistant: "\u5148\u6539\u4FDD\u5B58。\u518D\u5199\u51FA\u5B8C\u6574\u52A9\u624B\u6B63\u6587。",
    });
    assert.equal(messages.length, 2);
    assert.equal(messages[1]?.text, "\u5148\u6539\u4FDD\u5B58。\u518D\u5199\u51FA\u5B8C\u6574\u52A9\u624B\u6B63\u6587。");
  });

  it("\u5728\u52A9\u624B\u6B63\u6587\u524D\u4FDD\u7559\u601D\u8003\u8FC7\u7A0B", () => {
    const messages = buildConversationTranscript({
      sessionUser: "- \u4EFB\u52A1",
      live: [
        { role: "thinking", text: "\u5148\u6838\u5BF9\u5B57\u6BB5。" },
        { role: "assistant", text: "\u5DF2\u5199\u5165\u5BF9\u8BDD。" },
      ],
      fromTurns: [
        { role: "thinking", text: "\u5148\u6838\u5BF9\u5B57\u6BB5。\u518D\u8865\u5168\u601D\u8003。" },
        { role: "assistant", text: "\u5DF2\u5199\u5165\u5BF9\u8BDD。" },
      ],
    });
    assert.deepEqual(
      messages.map((item) => `${item.role}:${item.text}`),
      [
        "user:- \u4EFB\u52A1",
        "thinking:\u5148\u6838\u5BF9\u5B57\u6BB5。\u518D\u8865\u5168\u601D\u8003。",
        "assistant:\u5DF2\u5199\u5165\u5BF9\u8BDD。",
      ],
    );
  });
});
