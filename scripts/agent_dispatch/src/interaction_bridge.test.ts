import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  createAskUserTool,
  emitConversationSnapshot,
  INTERACTION_EVENT_PREFIX,
  interactionStdio,
} from "./interaction_bridge.ts";
import type { RoundDispatchJob } from "./types.ts";

describe("interaction_bridge", () => {
  it("ask_user 发出问题并等待对应回复文件", async () => {
    const dir = mkdtempSync(join(tmpdir(), "kanban-interaction-"));
    const job = {
      engine: "cursor",
      cwd: process.cwd(),
      prompt: "执行任务",
      mcpEndpoint: "http://full/mcp",
      cardLimit: 1,
      workerToken: "token",
      interactionDir: dir,
      outPath: "unused",
      round: {
        cardId: "card-a",
        sessionId: "session-a",
        agentEndpointUrl: "http://scoped/mcp",
        images: [],
        attachmentPaths: [],
        projectMcpTags: [],
      },
    } satisfies RoundDispatchJob;
    const output: string[] = [];
    const originalWrite = interactionStdio.write;
    interactionStdio.write = (line) => {
      output.push(line);
    };
    try {
      const tool = createAskUserTool(job);
      assert.ok(tool);
      const pending = tool.execute({ question: "请选择方案" }, {});
      await new Promise((resolve) => setTimeout(resolve, 20));
      const line = output.find((item) =>
        item.startsWith(INTERACTION_EVENT_PREFIX)
      );
      assert.ok(line);
      const event = JSON.parse(line.slice(INTERACTION_EVENT_PREFIX.length));
      assert.equal(event.cardId, "card-a");
      assert.equal(event.text, "请选择方案");
      writeFileSync(
        join(dir, `${event.requestId}.reply.json`),
        JSON.stringify({ text: "方案 A" }),
      );
      assert.equal(await pending, "方案 A");
    } finally {
      interactionStdio.write = originalWrite;
    }
  });

  it("会话结束时把完整用户与助手消息写入快照文件", () => {
    const dir = mkdtempSync(join(tmpdir(), "kanban-interaction-"));
    const job = {
      engine: "cursor",
      cwd: process.cwd(),
      prompt: "执行任务",
      mcpEndpoint: "http://full/mcp",
      cardLimit: 1,
      workerToken: "token",
      interactionDir: dir,
      outPath: "unused",
      round: {
        cardId: "card-a",
        sessionId: "session-a",
        agentEndpointUrl: "http://scoped/mcp",
        images: [],
        attachmentPaths: [],
        projectMcpTags: [],
      },
    } satisfies RoundDispatchJob;
    const output: string[] = [];
    const originalWrite = interactionStdio.write;
    interactionStdio.write = (line) => {
      output.push(line);
    };
    try {
      emitConversationSnapshot(job, [
        { role: "user", text: "- 标题" },
        { role: "assistant", text: "第一条助手。" },
        { role: "assistant", text: "第二条助手。" },
      ]);
      const line = output.find((item) =>
        item.startsWith(INTERACTION_EVENT_PREFIX)
      );
      assert.ok(line);
      const event = JSON.parse(line.slice(INTERACTION_EVENT_PREFIX.length));
      assert.equal(event.type, "snapshot");
      const snapshot = JSON.parse(
        readFileSync(join(dir, event.text), "utf8"),
      ) as { messages: unknown[] };
      assert.equal(snapshot.messages.length, 3);
    } finally {
      interactionStdio.write = originalWrite;
    }
  });
});
