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
  prompt: "基础指令",
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
    prompt: "本轮 prompt",
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
          workItems: [{ id: "work-a", text: "完成 A" }],
        };
      case "dispatch_agent_session_status":
        return {
          sessionOpen: true,
          pickClaimed: true,
          sessionId: "session-a",
          cardId: "card-a",
          projectId: "project-a",
          pending: {
            sessionId: "session-a",
            cardId: "card-a",
            status: "declared",
            ...(options?.manualReason
              ? { manualVerificationReason: options.manualReason }
              : {}),
          },
        };
      case "get_card":
        return { cardId: "card-a", columnId: "doing" };
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
    readArchitecture: () => "# 架构",
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
        : { ok: true, summary: "完成" };
    },
  };
  return { dependencies, full, scoped };
}

describe("run_batch", () => {
  it("批次开始先用新 token 恢复 committed 收尾", async () => {
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
      readArchitecture: () => "# 架构",
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

  it("claim、门禁、会话验证记账、finalize 形成完整单卡流程", async () => {
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

  it("收尾记账失败不误报为脏工作区停止", async () => {
    const { dependencies, full } = createHappyDependencies({
      recordError: "dispatch_record_validation_results 失败：验证结果数量与声明命令不一致",
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
    assert.match(result.error ?? "", /Worker 收尾失败/);
    assert.doesNotMatch(result.error ?? "", /工作区不干净，停止批次/);
  });

  it("禁止使用卡片参数时沿用工作台默认", async () => {
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

  it("默认脏工作区在领取前停止批次", async () => {
    const { dependencies, full } = createHappyDependencies();
    dependencies.inspectGit = () => ({ kind: "dirty", output: " M src/file.ts" });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /工作区不干净，未领取卡片/);
    assert.equal(
      full.calls.some((item) => item.name === "dispatch_claim_next_card"),
      false,
    );
  });

  it("工作台允许脏工作区时可以领取", async () => {
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

  it("卡片允许脏工作区时可以领取", async () => {
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

  it("禁止卡片参数时忽略卡片脏工作区开关", async () => {
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
    assert.match(result.error ?? "", /工作区不干净，未领取卡片/);
    assert.equal(
      full.calls.some((item) => item.name === "dispatch_claim_next_card"),
      false,
    );
  });

  it("scoped 工具不精确匹配时拒绝启动 Agent", async () => {
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
    assert.match(result.error ?? "", /scoped MCP 工具门禁失败/);
    assert.equal(agentStarted, false);
    assert.equal(scoped.closed, true);
    assert.ok(
      full.calls.some((item) => item.name === "dispatch_fail_agent_session"),
    );
  });

  it("skip 调用私有工具且脏工作区停止批次", async () => {
    const { dependencies, full } = createHappyDependencies({
      runAgent: async () => ({ ok: false, error: "已跳过" }),
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
    assert.match(result.error ?? "", /跳过后工作区不干净/);
    assert.ok(
      full.calls.some((item) => item.name === "dispatch_skip_agent_session"),
    );
  });

  it("人工验证原因也不复跑命令并直接 finalize", async () => {
    const { dependencies, full } = createHappyDependencies({
      manualReason: "需要人工检查视觉结果",
    });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, true);
    assert.ok(full.calls.some((item) => item.name === "dispatch_finalize"));
  });

  it("finalize 要求保留 pending 时不 fail 会话", async () => {
    const { dependencies, full } = createHappyDependencies({
      finalizeResult: {
        ok: false,
        sessionId: "session-a",
        cardId: "card-a",
        status: "committed",
        commitRef: "abc1234",
        error: "Git 提交后工作区不干净，拒绝更新看板",
        preservePending: true,
      },
    });

    const result = await runBatch(job, undefined, dependencies);

    assert.equal(result.ok, false);
    assert.equal(result.preservePending, true);
    assert.match(result.error ?? "", /工作区不干净/);
    assert.equal(
      full.calls.some((item) => item.name === "dispatch_fail_agent_session"),
      false,
    );
    assert.ok(full.calls.some((item) => item.name === "dispatch_finalize"));
  });

  it("peek 与 claim 卡片漂移时停止批次", async () => {
    const { dependencies } = createHappyDependencies({
      claimError: "下一张卡片已漂移：expectedCardId=card-a，actualCardId=card-b",
    });

    const result = await runBatch(job, undefined, dependencies);
    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /卡片已漂移/);
  });

  it("领卡前读取 liveFile，下一张使用更新后的默认模型", async () => {
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
        return { ok: true, summary: "完成" };
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
