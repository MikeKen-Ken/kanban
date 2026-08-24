import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { runAgentWithRetry } from "./run_agent_with_retry.ts";
import type { RoundDispatchJob } from "./types.ts";

const job: RoundDispatchJob = {
  engine: "cursor",
  cwd: process.cwd(),
  prompt: "\u5904\u7406\u5F53\u524D\u5361\u7247",
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
  it("\u6682\u65F6\u6545\u969C\u540E\u81EA\u52A8\u91CD\u8BD5\u5F53\u524D\u5361\u7247\u76F4\u81F3\u6210\u529F", async () => {
    let attempts = 0;
    const delays: number[] = [];

    const result = await runAgentWithRetry(
      async () => {
        attempts += 1;
        return attempts < 3
          ? { ok: false, error: "Cursor \u670D\u52A1\u6682\u65F6\u4E0D\u53EF\u7528", retryable: true }
          : { ok: true, summary: "\u5B8C\u6210" };
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

  it("\u4E94\u6B21\u6682\u65F6\u6545\u969C\u540E\u4E2D\u65AD\u5E76\u4FDD\u7559\u6700\u540E\u9519\u8BEF", async () => {
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

  it("\u8F83\u957F\u7F51\u7EDC\u6CE2\u52A8\u540E\u4ECD\u80FD\u5728\u5F53\u524D\u5361\u7247\u5185\u6062\u590D", async () => {
    let attempts = 0;
    const delays: number[] = [];

    const result = await runAgentWithRetry(
      async () => {
        attempts += 1;
        return attempts < 5
          ? { ok: false, error: "connection lost", retryable: true }
          : { ok: true, summary: "\u6062\u590D\u5E76\u5B8C\u6210" };
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

  it("\u4E0D\u53EF\u91CD\u8BD5\u9519\u8BEF\u7ACB\u5373\u8FD4\u56DE", async () => {
    let attempts = 0;

    const result = await runAgentWithRetry(
      async () => {
        attempts += 1;
        return { ok: false, error: "\u7F3A\u5C11 API Key", retryable: false };
      },
      job,
      undefined,
      async () => undefined,
    );

    assert.equal(result.ok, false);
    assert.equal(attempts, 1);
  });
});
