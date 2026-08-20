import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { CursorThinkingStream } from "./cursor_thinking_stream.ts";

function collect() {
  const lines: string[] = [];
  const stream = new CursorThinkingStream({
    intervalMs: 60_000,
    write: (line) => lines.push(line),
    schedule: () => ({ cancel() {} }),
  });
  return { lines, stream };
}

describe("cursor_thinking_stream", () => {
  it("发送任务时先说明空白不等于空闲", () => {
    const { lines, stream } = collect();
    stream.notePromptSent();
    assert.match(lines[0] ?? "", /等待模型思考流/);
    assert.equal(stream.consumeStreamedThinking(), false);
  });

  it("按行立刻打出思考增量，并跳过随后的整段步骤", () => {
    const { lines, stream } = collect();
    stream.handleDelta({ type: "thinking-delta", text: "第一行\n第二行\n" });
    assert.deepEqual(lines, ["思考：第一行", "  │ 第二行"]);
    stream.handleDelta({ type: "thinking-completed", thinkingDurationMs: 270_000 });
    assert.equal(lines.at(-1), "思考完成（270 秒）");
    assert.equal(stream.assembledText(), "第一行\n第二行");
    assert.equal(stream.consumeStreamedThinking(), true);
    assert.equal(stream.consumeStreamedThinking(), false);
  });

  it("快照式增量只追加新增部分", () => {
    const { lines, stream } = collect();
    stream.handleDelta({ type: "thinking-delta", text: "你好" });
    stream.handleDelta({ type: "thinking-delta", text: "你好世界" });
    stream.handleDelta({ type: "thinking-completed", thinkingDurationMs: 1000 });
    assert.deepEqual(lines, ["思考：你好世界", "思考完成（1 秒）"]);
  });

  it("没有增量时不吞掉 onStep 思考", () => {
    const { stream } = collect();
    stream.handleDelta({ type: "thinking-completed", thinkingDurationMs: 0 });
    assert.equal(stream.consumeStreamedThinking(), false);
  });

  it("接受 SDK thinking 消息与嵌套 text", () => {
    const { stream } = collect();
    stream.handleDelta({ type: "thinking", text: "完整思考步骤" });
    assert.equal(stream.assembledText(), "完整思考步骤");
    stream.handleDelta({
      type: "thinking-delta",
      message: { text: "后续一句" },
    });
    stream.handleDelta({ type: "thinking-completed", thinkingDurationMs: 0 });
    assert.equal(stream.assembledText(), "完整思考步骤后续一句");
  });
});
