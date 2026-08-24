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
  it("\u53D1\u9001\u4EFB\u52A1\u65F6\u5148\u8BF4\u660E\u7A7A\u767D\u4E0D\u7B49\u4E8E\u7A7A\u95F2", () => {
    const { lines, stream } = collect();
    stream.notePromptSent();
    assert.match(lines[0] ?? "", /waiting for the model thinking stream/);
    assert.equal(stream.consumeStreamedThinking(), false);
  });

  it("\u6309\u884C\u7ACB\u523B\u6253\u51FA\u601D\u8003\u589E\u91CF，\u5E76\u8DF3\u8FC7\u968F\u540E\u7684\u6574\u6BB5\u6B65\u9AA4", () => {
    const { lines, stream } = collect();
    stream.handleDelta({ type: "thinking-delta", text: "\u7B2C\u4E00\u884C\n\u7B2C\u4E8C\u884C\n" });
    assert.deepEqual(lines, ["Thinking: \u7B2C\u4E00\u884C", "  │ \u7B2C\u4E8C\u884C"]);
    stream.handleDelta({ type: "thinking-completed", thinkingDurationMs: 270_000 });
    assert.equal(lines.at(-1), "Thinking done (270s)");
    assert.equal(stream.assembledText(), "\u7B2C\u4E00\u884C\n\u7B2C\u4E8C\u884C");
    assert.equal(stream.consumeStreamedThinking(), true);
    assert.equal(stream.consumeStreamedThinking(), false);
  });

  it("\u5FEB\u7167\u5F0F\u589E\u91CF\u53EA\u8FFD\u52A0\u65B0\u589E\u90E8\u5206", () => {
    const { lines, stream } = collect();
    stream.handleDelta({ type: "thinking-delta", text: "\u4F60\u597D" });
    stream.handleDelta({ type: "thinking-delta", text: "\u4F60\u597D\u4E16\u754C" });
    stream.handleDelta({ type: "thinking-completed", thinkingDurationMs: 1000 });
    assert.deepEqual(lines, ["Thinking: \u4F60\u597D\u4E16\u754C", "Thinking done (1s)"]);
  });

  it("\u6CA1\u6709\u589E\u91CF\u65F6\u4E0D\u541E\u6389 onStep \u601D\u8003", () => {
    const { stream } = collect();
    stream.handleDelta({ type: "thinking-completed", thinkingDurationMs: 0 });
    assert.equal(stream.consumeStreamedThinking(), false);
  });

  it("\u63A5\u53D7 SDK thinking \u6D88\u606F\u4E0E\u5D4C\u5957 text", () => {
    const { stream } = collect();
    stream.handleDelta({ type: "thinking", text: "\u5B8C\u6574\u601D\u8003\u6B65\u9AA4" });
    assert.equal(stream.assembledText(), "\u5B8C\u6574\u601D\u8003\u6B65\u9AA4");
    stream.handleDelta({
      type: "thinking-delta",
      message: { text: "\u540E\u7EED\u4E00\u53E5" },
    });
    stream.handleDelta({ type: "thinking-completed", thinkingDurationMs: 0 });
    assert.equal(stream.assembledText(), "\u5B8C\u6574\u601D\u8003\u6B65\u9AA4\u540E\u7EED\u4E00\u53E5");
  });
});
