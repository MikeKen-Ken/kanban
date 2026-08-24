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
  it("ask_user \u53D1\u51FA\u95EE\u9898\u5E76\u7B49\u5F85\u5BF9\u5E94\u56DE\u590D\u6587\u4EF6", async () => {
    const dir = mkdtempSync(join(tmpdir(), "kanban-interaction-"));
    const job = {
      engine: "cursor",
      cwd: process.cwd(),
      prompt: "\u6267\u884C\u4EFB\u52A1",
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
      const pending = tool.execute({ question: "\u8BF7\u9009\u62E9\u65B9\u6848" }, {});
      await new Promise((resolve) => setTimeout(resolve, 20));
      const line = output.find((item) =>
        item.startsWith(INTERACTION_EVENT_PREFIX)
      );
      assert.ok(line);
      const event = JSON.parse(line.slice(INTERACTION_EVENT_PREFIX.length));
      assert.equal(event.cardId, "card-a");
      assert.equal(event.text, "\u8BF7\u9009\u62E9\u65B9\u6848");
      writeFileSync(
        join(dir, `${event.requestId}.reply.json`),
        JSON.stringify({ text: "\u65B9\u6848 A" }),
      );
      assert.equal(await pending, "\u65B9\u6848 A");
    } finally {
      interactionStdio.write = originalWrite;
    }
  });

  it("\u95EE\u9898\u6B63\u6587\u4E2D\u7684\u7F16\u53F7\u5217\u8868\u4F1A\u5199\u5165\u63D0\u95EE\u4E8B\u4EF6", async () => {
    const dir = mkdtempSync(join(tmpdir(), "kanban-interaction-"));
    const job = {
      engine: "cursor",
      cwd: process.cwd(),
      prompt: "\u6267\u884C\u4EFB\u52A1",
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
      const pending = tool.execute(
        {
          question:
            "\u8BF7\u9009\u62E9\u65B9\u6848\n1. \u672C\u673A\u5DF2\u662F\u6700\u65B0\n2. \u5F3A\u5236\u4F7F\u7528 pwsh\n3. \u4EC5\u6267\u884C winget upgrade",
        },
        {},
      );
      await new Promise((resolve) => setTimeout(resolve, 20));
      const line = output.find((item) =>
        item.startsWith(INTERACTION_EVENT_PREFIX)
      );
      assert.ok(line);
      const event = JSON.parse(line.slice(INTERACTION_EVENT_PREFIX.length));
      assert.deepEqual(event.choices, [
        "\u672C\u673A\u5DF2\u662F\u6700\u65B0",
        "\u5F3A\u5236\u4F7F\u7528 pwsh",
        "\u4EC5\u6267\u884C winget upgrade",
      ]);
      writeFileSync(
        join(dir, `${event.requestId}.reply.json`),
        JSON.stringify({ text: "\u672C\u673A\u5DF2\u662F\u6700\u65B0" }),
      );
      assert.equal(await pending, "\u672C\u673A\u5DF2\u662F\u6700\u65B0");
    } finally {
      interactionStdio.write = originalWrite;
    }
  });

  it("ask_user \u4F1A\u628A\u4E92\u65A5\u9009\u9879\u5199\u5165\u63D0\u95EE\u4E8B\u4EF6", async () => {
    const dir = mkdtempSync(join(tmpdir(), "kanban-interaction-"));
    const job = {
      engine: "cursor",
      cwd: process.cwd(),
      prompt: "\u6267\u884C\u4EFB\u52A1",
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
      const pending = tool.execute(
        {
          question: "\u8BF7\u9009\u62E9\u65B9\u6848",
          choices: ["\u65B9\u6848 A", "\u65B9\u6848 B", "\u65B9\u6848 C"],
        },
        {},
      );
      await new Promise((resolve) => setTimeout(resolve, 20));
      const line = output.find((item) =>
        item.startsWith(INTERACTION_EVENT_PREFIX)
      );
      assert.ok(line);
      const event = JSON.parse(line.slice(INTERACTION_EVENT_PREFIX.length));
      assert.deepEqual(event.choices, ["\u65B9\u6848 A", "\u65B9\u6848 B", "\u65B9\u6848 C"]);
      writeFileSync(
        join(dir, `${event.requestId}.reply.json`),
        JSON.stringify({ text: "\u65B9\u6848 B" }),
      );
      assert.equal(await pending, "\u65B9\u6848 B");
    } finally {
      interactionStdio.write = originalWrite;
    }
  });

  it("\u4F1A\u8BDD\u7ED3\u675F\u65F6\u628A\u5B8C\u6574\u7528\u6237\u4E0E\u52A9\u624B\u6D88\u606F\u5199\u5165\u5FEB\u7167\u6587\u4EF6", () => {
    const dir = mkdtempSync(join(tmpdir(), "kanban-interaction-"));
    const job = {
      engine: "cursor",
      cwd: process.cwd(),
      prompt: "\u6267\u884C\u4EFB\u52A1",
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
        { role: "user", text: "- \u6807\u9898" },
        { role: "assistant", text: "\u7B2C\u4E00\u6761\u52A9\u624B。" },
        { role: "assistant", text: "\u7B2C\u4E8C\u6761\u52A9\u624B。" },
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
