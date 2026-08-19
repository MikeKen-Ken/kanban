import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildConversationTranscript } from "./conversation_transcript.ts";

describe("conversation_transcript", () => {
  it("保留会话用户消息，并写入每一条助手正文", () => {
    const messages = buildConversationTranscript({
      sessionUser: "- 标题\n- 描述",
      fromTurns: [
        {
          role: "user",
          text: "# Worker 注入的本轮上下文\n完整 prompt",
        },
        { role: "assistant", text: "先定位写入逻辑。" },
        { role: "assistant", text: "再补全所有助手消息。" },
      ],
    });
    assert.deepEqual(messages, [
      { role: "user", text: "- 标题\n- 描述" },
      { role: "assistant", text: "先定位写入逻辑。" },
      { role: "assistant", text: "再补全所有助手消息。" },
    ]);
  });

  it("会话快照缺助手时回退到实时记录，并保留追问用户消息", () => {
    const messages = buildConversationTranscript({
      sessionUser: "- 任务",
      live: [
        { role: "user", text: "- 任务" },
        { role: "assistant", text: "请确认方案" },
        { role: "user", text: "用方案 A" },
        { role: "assistant", text: "开始改。" },
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
      ["user:- 任务", "assistant:请确认方案", "user:用方案 A", "assistant:开始改。"],
    );
  });

  it("用更长的会话快照升级同一条流式助手消息", () => {
    const messages = buildConversationTranscript({
      sessionUser: "开始",
      live: [{ role: "assistant", text: "先改保存。" }],
      fromTurns: [
        { role: "assistant", text: "先改保存。再写出完整助手正文。" },
      ],
      trailingAssistant: "先改保存。再写出完整助手正文。",
    });
    assert.equal(messages.length, 2);
    assert.equal(messages[1]?.text, "先改保存。再写出完整助手正文。");
  });
});
