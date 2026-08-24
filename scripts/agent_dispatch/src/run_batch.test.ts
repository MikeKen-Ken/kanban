import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import type { CallToolResult } from "@modelcontextprotocol/client";
import type { KanbanMcpConnection } from "./mcp_client.ts";
import { runBatch, type RunBatchDependencies } from "./run_batch.ts";
import type { SessionContext } from "./session_context.ts";
import type { DispatchJob, RoundDispatchJob } from "./types.ts";

const job: DispatchJob = {
  engine: "cursor",
  cwd: process.cwd(),
  prompt: "\u57FA\u7840\u6307\u4EE4",
  mcpEndpoint: "http://full/mcp",
  projectId: "project-a",
  cardLimit: 1,
  workerToken: "worker-secret",
  outPath: "unused.json",
};

class FakeMcp implements KanbanMcpConnection {
  readonly calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  closed = false;
  private readonly jsonHandler: (
    name: string,
    args: Record<string, unknown>,
  ) => Record<string, unknown>;
  private readonly tools: string[];

  constructor(
    jsonHandler: (
      name: string,
      args: Record<string, unknown>,
    ) => Record<string, unknown>,
    tools: string[] = [],
  ) {
    this.jsonHandler = jsonHandler;
    this.tools = tools;
  }

  async listTools(): Promise<string[]> {
    return [...this.tools].sort();
  }

  async callRaw(
    name: string,
    args: Record<string, unknown>,
  ): Promise<CallToolResult> {
    this.calls.push({ name, args });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(this.jsonHandler(name, args)),
        },
        { type: "image", data: "aW1hZ2U=", mimeType: "image/png" },
      ],
    } as CallToolResult;
  }

  async callJson(
    name: string,
    args: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    this.calls.push({ name, args });
    return this.jsonHandler(name, args);
  }

  async close(): Promise<void> {
    this.closed = true;
  }
}

function makeContext(): SessionContext {
  return {
    prompt: "\u672C\u8F6E prompt",
    images: [{ data: "aW1hZ2U=", mimeType: "image/png" }],
    attachmentPaths: ["C:\\temp\\image.png"],
    tempDir: "C:\\temp",
    cleanup: () => undefined,
  };
}

function createHappyDependencies(options?: {
  scopedTools?: string[];
  expectedReasoning?: string;
  manualReason?: string;
  claimError?: string;
  recordError?: string;
  finalizeResult?: Record<string, unknown>;
  peekFields?: Record<string, unknown>;
  cardColumnId?: string;
  cardColumnName?: string;
  consultationSubmitted?: boolean;
  runAgent?: (round: RoundDispatchJob) => Promise<{ ok: boolean; error?: string }>;
}): {
  dependencies: RunBatchDependencies;
  full: FakeMcp;
  scoped: FakeMcp;
} {
  let peeked = false;
  const full = new FakeMcp((name) => {
    switch (name) {
      case "dispatch_list_pending":
        return { ok: true, pending: [] };
      case "peek_next_card":
        if (peeked) return { found: false };
        peeked = true;
        return { found: true, cardId: "card-a", ...options?.peekFields };
      case "dispatch_claim_next_card":
        if (options?.claimError) {
          throw new Error(options.claimError);
        }
        return {
          found: true,
          projectId: "project-a",
          cardId: "card-a",
          sessionId: "session-a",
          agentEndpointUrl: "http://scoped/mcp",
          agentModelParamValues: { reasoning_effort: "high" },
          ...options?.peekFields,
          workItems: [{ id: "work-a", text: "\u5B8C\u6210 A" }],
        };
      case "dispatch_agent_session_status":
        return {
          sessionOpen: true,
          pickClaimed: true,
          sessionId: "session-a",
          cardId: "card-a",
          projectId: "project-a",
          ...(options?.consultationSubmitted
            ? {}
            : {
                pending: {
                  sessionId: "session-a",
                  cardId: "card-a",
                  status: "declared",
                  ...(options?.manualReason
                    ? { manualVerificationReason: options.manualReason }
                    : {}),
                },
              }),
        };
      case "get_card":
        return {
          cardId: "card-a",
          columnId: options?.cardColumnId ?? "doing",
          ...(options?.cardColumnName
            ? { columnName: options.cardColumnName }
            : {}),
        };
      case "dispatch_record_validation_results":
        if (options?.recordError) {
          throw new Error(options.recordError);
        }
        return {
          sessionId: "session-a",
          cardId: "card-a",
          status: "validated",
        };
      case "dispatch_finalize":
        return options?.finalizeResult ?? {
          sessionId: "session-a",
          cardId: "card-a",
          status: "finalized",
        };
      default:
        return { ok: true };
    }
  });
  const scoped = new FakeMcp(
    () => ({ ok: true }),
    options?.scopedTools ?? [
      "ready_to_submit",
      "submit_consultation",
      "block_card",
    ],
  );
  const dependencies: RunBatchDependencies = {
    connectMcp: async (endpoint) =>
      endpoint.includes("scoped") ? scoped : full,
    inspectGit: () => ({ kind: "clean" }),
    readArchitecture: () => "# \u67B6\u6784",
    createContext: () => makeContext(),
    runAgent: async (round) => {
      assert.equal(round.round.cardId, "card-a");
      assert.equal(round.round.images.length, 1);
      assert.deepEqual(
          round.round.projectMcpTags,
          Array.isArray(options?.peekFields?.projectMcpTags)
            ? options.peekFields.projectMcpTags
            : [],
      );
      assert.equal(
        round.modelParams?.find((item) => item.id === "reasoning_effort")?.value,
        options?.expectedReasoning ?? "high",
      );
      return options?.runAgent
        ? options.runAgent(round)
        : { ok: true, summary: "\u5B8C\u6210" };
    },
  };
  return { dependencies, full, scoped };
}

describe("run_batch", () => {
  it("accepts a consultation card in a custom Verify column without ready_to_submit", async () => {
    const { dependencies } = createHappyDependencies({
      cardColumnId: "custom-verify",
      cardColumnName: "Verify",
      consultationSubmitted: true,
    });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, true);
    assert.equal(result.processedCards, 1);
  });

  it("\u6279\u6B21\u5F00\u59CB\u5148\u7528\u65B0 token \u6062\u590D committed \u6536\u5C3E", async () => {
    const full = new FakeMcp((name) => {
      switch (name) {
        case "dispatch_list_pending":
          return {
            pending: [{
              sessionId: "old-session",
              cardId: "old-card",
              status: "committed",
            }],
          };
        case "dispatch_recover":
          return {
            sessionId: "old-session",
            cardId: "old-card",
            status: "committed",
          };
        case "dispatch_finalize":
          return {
            sessionId: "old-session",
            cardId: "old-card",
            status: "finalized",
          };
        case "peek_next_card":
          return { found: false };
        default:
          return { ok: true };
      }
    });
    const dependencies: RunBatchDependencies = {
      connectMcp: async () => full,
      inspectGit: () => ({ kind: "clean" }),
      readArchitecture: () => "# \u67B6\u6784",
      createContext: () => makeContext(),
      runAgent: async () => ({ ok: true }),
    };

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, true);
    assert.equal(result.processedCards, 1);
    assert.deepEqual(
      full.calls
        .filter((item) => item.name.startsWith("dispatch_"))
        .map((item) => item.name),
      ["dispatch_list_pending", "dispatch_recover", "dispatch_finalize"],
    );
  });

  it("\u961F\u5217\u4E3A\u7A7A\u65F6\u4E0D\u5199\u7A7A\u7684\u5355\u5361\u8F6E\u6B21\u65E5\u5FD7", async () => {
    const full = new FakeMcp((name) => {
      switch (name) {
        case "dispatch_list_pending":
          return { ok: true, pending: [] };
        case "peek_next_card":
          return { found: false };
        default:
          return { ok: true };
      }
    });
    const dependencies: RunBatchDependencies = {
      connectMcp: async () => full,
      inspectGit: () => ({ kind: "clean" }),
      readArchitecture: () => "# \u67B6\u6784",
      createContext: () => makeContext(),
      runAgent: async () => ({ ok: true }),
    };
    const chunks: string[] = [];
    const originalWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = ((chunk: unknown, ...args: unknown[]) => {
      chunks.push(String(chunk));
      return originalWrite(chunk as never, ...(args as never[]));
    }) as typeof process.stdout.write;

    try {
      const result = await runBatch(job, undefined, dependencies);
      assert.equal(result.ok, true);
      assert.equal(result.processedCards, 0);
    } finally {
      process.stdout.write = originalWrite;
    }

    assert.equal(chunks.join("").includes("Worker \u5355\u5361\u8F6E\u6B21"), false);
  });

  it("claim、\u95E8\u7981、\u4F1A\u8BDD\u9A8C\u8BC1\u8BB0\u8D26、finalize \u5F62\u6210\u5B8C\u6574\u5355\u5361\u6D41\u7A0B", async () => {
    const { dependencies, full, scoped } = createHappyDependencies({
      peekFields: { projectMcpTags: ["unity"] },
    });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, true);
    assert.equal(result.processedCards, 1);
    assert.ok(full.calls.some((item) => item.name === "dispatch_claim_next_card"));
    const recorded = full.calls.find(
      (item) => item.name === "dispatch_record_validation_results",
    );
    assert.deepEqual(recorded?.args.results, []);
    assert.ok(full.calls.some((item) => item.name === "dispatch_finalize"));
    assert.ok(full.calls.some((item) => item.name === "dispatch_close_agent_session"));
    assert.equal(scoped.closed, true);
  });

  it("\u6536\u5C3E\u8BB0\u8D26\u5931\u8D25\u4E0D\u8BEF\u62A5\u4E3A\u810F\u5DE5\u4F5C\u533A\u505C\u6B62", async () => {
    const { dependencies, full } = createHappyDependencies({
      recordError: "dispatch_record_validation_results \u5931\u8D25：\u9A8C\u8BC1\u7ED3\u679C\u6570\u91CF\u4E0E\u58F0\u660E\u547D\u4EE4\u4E0D\u4E00\u81F4",
    });
    dependencies.inspectGit = () => {
      const claimed = full.calls.some(
        (item) => item.name === "dispatch_claim_next_card",
      );
      return claimed
        ? { kind: "dirty", output: " M app/lib/foo.dart" }
        : { kind: "clean" };
    };

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /Worker finalization failed/);
    assert.doesNotMatch(result.error ?? "", /\u5DE5\u4F5C\u533A\u4E0D\u5E72\u51C0，\u505C\u6B62\u6279\u6B21/);
  });

  it("\u7981\u6B62\u4F7F\u7528\u5361\u7247\u53C2\u6570\u65F6\u6CBF\u7528\u5DE5\u4F5C\u53F0\u9ED8\u8BA4", async () => {
    const { dependencies } = createHappyDependencies({
      expectedReasoning: "medium",
    });

    const result = await runBatch(
      {
        ...job,
        ignoreCardParams: true,
        modelParams: [{ id: "reasoning_effort", value: "medium" }],
      },
      undefined,
      dependencies,
    );

    assert.equal(result.ok, true);
  });

  it("\u9ED8\u8BA4\u810F\u5DE5\u4F5C\u533A\u5728\u9886\u53D6\u524D\u505C\u6B62\u6279\u6B21", async () => {
    const { dependencies, full } = createHappyDependencies();
    dependencies.inspectGit = () => ({ kind: "dirty", output: " M src/file.ts" });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /Workspace is dirty; card was not claimed/);
    assert.equal(
      full.calls.some((item) => item.name === "dispatch_claim_next_card"),
      false,
    );
  });

  it("\u5DE5\u4F5C\u53F0\u5141\u8BB8\u810F\u5DE5\u4F5C\u533A\u65F6\u53EF\u4EE5\u9886\u53D6", async () => {
    const { dependencies, full } = createHappyDependencies();
    dependencies.inspectGit = () => ({ kind: "dirty", output: " M src/file.ts" });

    const result = await runBatch(
      { ...job, allowDirtyWorkspace: true },
      undefined,
      dependencies,
    );

    assert.equal(result.ok, true);
    assert.ok(
      full.calls.some((item) => item.name === "dispatch_claim_next_card"),
    );
  });

  it("\u5361\u7247\u5141\u8BB8\u810F\u5DE5\u4F5C\u533A\u65F6\u53EF\u4EE5\u9886\u53D6", async () => {
    const { dependencies, full } = createHappyDependencies({
      peekFields: { agentAllowDirtyWorkspace: true },
    });
    dependencies.inspectGit = () => ({ kind: "dirty", output: " M src/file.ts" });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, true);
    assert.ok(
      full.calls.some((item) => item.name === "dispatch_claim_next_card"),
    );
  });

  it("\u7981\u6B62\u5361\u7247\u53C2\u6570\u65F6\u5FFD\u7565\u5361\u7247\u810F\u5DE5\u4F5C\u533A\u5F00\u5173", async () => {
    const { dependencies, full } = createHappyDependencies({
      peekFields: { agentAllowDirtyWorkspace: true },
    });
    dependencies.inspectGit = () => ({ kind: "dirty", output: " M src/file.ts" });

    const result = await runBatch(
      { ...job, ignoreCardParams: true },
      undefined,
      dependencies,
    );

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /Workspace is dirty; card was not claimed/);
    assert.equal(
      full.calls.some((item) => item.name === "dispatch_claim_next_card"),
      false,
    );
  });

  it("scoped \u5DE5\u5177\u4E0D\u7CBE\u786E\u5339\u914D\u65F6\u62D2\u7EDD\u542F\u52A8 Agent", async () => {
    let agentStarted = false;
    const { dependencies, full, scoped } = createHappyDependencies({
      scopedTools: ["ready_to_submit", "block_card"],
      runAgent: async () => {
        agentStarted = true;
        return { ok: true };
      },
    });

    const result = await runBatch(job, undefined, dependencies);
    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /Scoped MCP tool gate failed/);
    assert.equal(agentStarted, false);
    assert.equal(scoped.closed, true);
    assert.ok(
      full.calls.some((item) => item.name === "dispatch_fail_agent_session"),
    );
  });

  it("skip \u8C03\u7528\u79C1\u6709\u5DE5\u5177\u4E14\u810F\u5DE5\u4F5C\u533A\u505C\u6B62\u6279\u6B21", async () => {
    const { dependencies, full } = createHappyDependencies({
      runAgent: async () => ({ ok: false, error: "Skipped" }),
    });
    let inspections = 0;
    dependencies.inspectGit = () => {
      inspections += 1;
      return inspections === 1
        ? { kind: "clean" }
        : { kind: "dirty", output: " M src/file.ts" };
    };

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /Workspace is dirty after skip/);
    assert.ok(
      full.calls.some((item) => item.name === "dispatch_skip_agent_session"),
    );
  });

  it("\u4EBA\u5DE5\u9A8C\u8BC1\u539F\u56E0\u4E5F\u4E0D\u590D\u8DD1\u547D\u4EE4\u5E76\u76F4\u63A5 finalize", async () => {
    const { dependencies, full } = createHappyDependencies({
      manualReason: "\u9700\u8981\u4EBA\u5DE5\u68C0\u67E5\u89C6\u89C9\u7ED3\u679C",
    });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, true);
    assert.ok(full.calls.some((item) => item.name === "dispatch_finalize"));
  });

  it("finalize \u8981\u6C42\u4FDD\u7559 pending \u65F6\u4E0D fail \u4F1A\u8BDD", async () => {
    const { dependencies, full } = createHappyDependencies({
      finalizeResult: {
        ok: false,
        sessionId: "session-a",
        cardId: "card-a",
        status: "committed",
        commitRef: "abc1234",
        error: "Git \u63D0\u4EA4\u540E\u5DE5\u4F5C\u533A\u4E0D\u5E72\u51C0，\u62D2\u7EDD\u66F4\u65B0\u770B\u677F",
        preservePending: true,
      },
    });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, false);
    assert.equal(result.preservePending, true);
    assert.match(result.error ?? "", /\u5DE5\u4F5C\u533A\u4E0D\u5E72\u51C0/);
    assert.equal(
      full.calls.some((item) => item.name === "dispatch_fail_agent_session"),
      false,
    );
    assert.ok(full.calls.some((item) => item.name === "dispatch_finalize"));
  });

  it("peek \u4E0E claim \u5361\u7247\u6F02\u79FB\u65F6\u505C\u6B62\u6279\u6B21", async () => {
    const { dependencies } = createHappyDependencies({
      claimError: "\u4E0B\u4E00\u5F20\u5361\u7247\u5DF2\u6F02\u79FB：expectedCardId=card-a，actualCardId=card-b",
    });

    const result = await runBatch(job, undefined, dependencies);
    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /\u5361\u7247\u5DF2\u6F02\u79FB/);
  });

  it("\u9886\u5361\u524D\u8BFB\u53D6 liveFile，\u4E0B\u4E00\u5F20\u4F7F\u7528\u66F4\u65B0\u540E\u7684\u9ED8\u8BA4\u6A21\u578B", async () => {
    const dir = mkdtempSync(join(tmpdir(), "kanban-live-"));
    const liveFile = join(dir, "live.json");
    writeFileSync(
      liveFile,
      JSON.stringify({
        model: "composer-2.5",
        modelParams: [{ id: "reasoning_effort", value: "low" }],
      }),
    );
    const { dependencies } = createHappyDependencies({
      expectedReasoning: "low",
      runAgent: async (round) => {
        assert.equal(round.model, "composer-2.5");
        return { ok: true, summary: "\u5B8C\u6210" };
      },
    });

    const result = await runBatch(
      {
        ...job,
        model: "old-model",
        ignoreCardParams: true,
        liveFile,
      },
      undefined,
      dependencies,
    );
    assert.equal(result.ok, true);
  });
});
