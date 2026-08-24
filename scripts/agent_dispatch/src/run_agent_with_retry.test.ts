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
  it("retries the current card after temporary failures until it succeeds", async () => {
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

  it("stops after five temporary failures and preserves the last error", async () => {
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

  it("recovers the current card after a longer network interruption", async () => {
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

  it("returns immediately for a non-retryable error", async () => {
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
