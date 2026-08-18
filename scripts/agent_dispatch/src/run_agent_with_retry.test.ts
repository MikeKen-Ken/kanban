import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { runAgentWithRetry } from "./run_agent_with_retry.ts";
import type { RoundDispatchJob } from "./types.ts";

const job: RoundDispatchJob = {
  engine: "cursor",
  cwd: process.cwd(),
  prompt: "处理当前卡片",
  mcpEndpoint: "http://full/mcp",
  cardLimit: 1,
  workerToken: "worker-token",
  outPath: "unused.json",
  round: {
    cardId: "card-a",
    sessionId: "session-a",
    agentEndpointUrl: "http://scoped/mcp",
    images: [],
    attachmentPaths: [],
    projectMcpTags: [],
  },
};

describe("run_agent_with_retry", () => {
  it("暂时故障后自动重试当前卡片直至成功", async () => {
    let attempts = 0;
    const delays: number[] = [];

    const result = await runAgentWithRetry(
      async () => {
        attempts += 1;
        return attempts < 3
          ? { ok: false, error: "Cursor 服务暂时不可用", retryable: true }
          : { ok: true, summary: "完成" };
      },
      job,
      undefined,
      async (ms) => {
        delays.push(ms);
      },
    );

    assert.equal(result.ok, true);
    assert.equal(attempts, 3);
    assert.deepEqual(delays, [1000, 2000]);
  });

  it("五次暂时故障后中断并保留最后错误", async () => {
    let attempts = 0;

    const result = await runAgentWithRetry(
      async () => {
        attempts += 1;
        return { ok: false, error: "ETIMEDOUT" };
      },
      job,
      undefined,
      async () => undefined,
    );

    assert.equal(result.ok, false);
    assert.equal(result.error, "ETIMEDOUT");
    assert.equal(attempts, 5);
  });

  it("较长网络波动后仍能在当前卡片内恢复", async () => {
    let attempts = 0;
    const delays: number[] = [];

    const result = await runAgentWithRetry(
      async () => {
        attempts += 1;
        return attempts < 5
          ? { ok: false, error: "connection lost", retryable: true }
          : { ok: true, summary: "恢复并完成" };
      },
      job,
      undefined,
      async (ms) => {
        delays.push(ms);
      },
    );

    assert.equal(result.ok, true);
    assert.equal(attempts, 5);
    assert.deepEqual(delays, [1000, 2000, 4000, 8000]);
  });

  it("不可重试错误立即返回", async () => {
    let attempts = 0;

    const result = await runAgentWithRetry(
      async () => {
        attempts += 1;
        return { ok: false, error: "缺少 API Key", retryable: false };
      },
      job,
      undefined,
      async () => undefined,
    );

    assert.equal(result.ok, false);
    assert.equal(attempts, 1);
  });
});
