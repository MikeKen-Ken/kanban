import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  createAskUserTool,
  INTERACTION_EVENT_PREFIX,
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
    const originalWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = ((chunk: string | Uint8Array) => {
      output.push(String(chunk));
      return true;
    }) as typeof process.stdout.write;
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
      process.stdout.write = originalWrite;
    }
  });
});
