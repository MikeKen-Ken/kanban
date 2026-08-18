import { WorkerCancelledError, type WorkerCancellation } from "./cancellation.ts";
import {
  inspectGitWorkingTree,
  type GitWorkingTree,
} from "./git_working_tree.ts";
import {
  KanbanMcpClient,
  parseClaimResult,
  type KanbanMcpConnection,
  type ParsedClaimResult,
} from "./mcp_client.ts";
import { runCodex } from "./run_codex.ts";
import { runCursor } from "./run_cursor.ts";
import {
  createSessionContext,
  readBatchArchitecture,
  type SessionContext,
} from "./session_context.ts";
import { readUserCursorRules, type UserRuleBundle } from "./user_rules.ts";
import { parseProjectMcpTags } from "./dispatch_mcp_allowlist.ts";
import { DISPATCH_SCOPED_TOOL_NAMES } from "./dispatch_scoped_tool_prompt.ts";
import {
  applyLiveJobOverlay,
  mergeJobWithCardOverrides,
  type DispatchJob,
  type DispatchResult,
  type RoundDispatchJob,
} from "./types.ts";
import { workerLog } from "./worker_log.ts";
import { readFileSync } from "node:fs";

export type RunBatchDependencies = {
  connectMcp(endpoint: string): Promise<KanbanMcpConnection>;
  inspectGit(cwd: string): GitWorkingTree;
  readArchitecture(cwd: string): string;
  readUserRules?(): UserRuleBundle;
  createContext(options: {
    basePrompt: string;
    architecture: string;
    userRules?: string;
    claim: ParsedClaimResult;
  }): SessionContext;
  runAgent(
    job: RoundDispatchJob,
    cancellation?: WorkerCancellation,
  ): Promise<DispatchResult>;
};

const defaultDependencies: RunBatchDependencies = {
  connectMcp: async (endpoint) => {
    const client = new KanbanMcpClient();
    await client.connect(endpoint);
    return client;
  },
  inspectGit: inspectGitWorkingTree,
  readArchitecture: readBatchArchitecture,
  readUserRules: readUserCursorRules,
  createContext: createSessionContext,
  runAgent: (roundJob, cancellation) =>
    roundJob.engine === "codex"
      ? runCodex(roundJob, cancellation)
      : runCursor(roundJob, cancellation),
};

export async function runBatch(
  job: DispatchJob,
  cancellation?: WorkerCancellation,
  dependencies: RunBatchDependencies = defaultDependencies,
): Promise<DispatchResult> {
  const limit = Math.max(1, Math.min(999, Math.trunc(job.cardLimit)));
  const architecture = dependencies.readArchitecture(job.cwd);
  const userRules = dependencies.readUserRules?.() ?? {
    text: "",
    count: 0,
    bytes: 0,
  };
  const mcp = await dependencies.connectMcp(job.mcpEndpoint);
  let processedCards = 0;
  workerLog(`Worker 批次启动：endpoint=${job.mcpEndpoint} limit=${limit}`);
  workerLog(
    `用户 Rule 注入：${userRules.count} 个，${userRules.bytes} bytes；不加载用户 Skill`,
  );

  const cancelledResult = (): DispatchResult => ({
    ok: false,
    error: "已取消",
    processedCards,
  });
  const drainedResult = (): DispatchResult => ({
    ok: true,
    summary: `已在当前会话结束后停止；已处理 ${processedCards} 张`,
    processedCards,
  });

  try {
    workerLog("Worker 已连接完整看板 MCP，正在恢复未完成收尾");
    const recovery = await recoverPendingSessions(
      mcp,
      job,
    );
    if (!recovery.ok) {
      return { ...recovery, processedCards };
    }
    processedCards += recovery.processedCards ?? 0;

    for (let index = 1; index <= limit; index += 1) {
      if (cancellation?.shouldStopAfterCurrentSession) {
        return cancellation.isCancelled ? cancelledResult() : drainedResult();
      }
      const liveJob = readLiveJob(job);
      const roundLabel = limit >= 999 ? `${index}` : `${index}/${limit}`;
      workerLog(`──────── Worker 单卡轮次 ${roundLabel} ────────`);
      const peek = await mcp.callJson("peek_next_card", {
        ...(liveJob.projectId ? { projectId: liveJob.projectId } : {}),
      });
      if (peek.found !== true) {
        return completedResult(processedCards, "当前无更多卡片");
      }

      const preview = mergeJobWithCardOverrides(liveJob, peek);
      const tree = dependencies.inspectGit(job.cwd);
      if (tree.kind === "dirty" && preview.allowDirtyWorkspace === true) {
        workerLog(`已允许脏工作区，继续领取：\n${tree.output}`);
      } else {
        const treeError = gitPreflightError(tree);
        if (treeError) {
          return { ok: false, error: treeError, processedCards };
        }
      }

      const expectedCardId = String(peek.cardId ?? "").trim();
      const claim = parseClaimResult(
        await mcp.callRaw("dispatch_claim_next_card", {
          workerToken: job.workerToken,
          ...(expectedCardId ? { expectedCardId } : {}),
        }),
      );
      if (claim.payload.found !== true) {
        return completedResult(processedCards, "claim 时队列已为空");
      }

      const cardId = requiredString(claim.payload, "cardId");
      const sessionId = requiredString(claim.payload, "sessionId");
      const agentEndpointUrl = requiredString(
        claim.payload,
        "agentEndpointUrl",
      );
      let scoped: KanbanMcpConnection | undefined;
      let context: SessionContext | undefined;
      let terminalRecorded = false;
      let allowDirtyWorkspace = preview.allowDirtyWorkspace === true;
      let postAgent = false;
      try {
        scoped = await dependencies.connectMcp(agentEndpointUrl);
        const tools = await scoped.listTools();
        if (JSON.stringify(tools) !== JSON.stringify(DISPATCH_SCOPED_TOOL_NAMES)) {
          throw new Error(
            `scoped MCP 工具门禁失败：实际=${tools.join(",")}，期望=${DISPATCH_SCOPED_TOOL_NAMES.join(",")}`,
          );
        }

        context = dependencies.createContext({
          basePrompt: job.prompt,
          architecture,
          userRules: userRules.text,
          claim,
        });
        const overridden = mergeJobWithCardOverrides(liveJob, claim.payload);
        allowDirtyWorkspace = overridden.allowDirtyWorkspace === true;
        const roundJob: RoundDispatchJob = {
          ...overridden,
          prompt: context.prompt,
          round: {
            cardId,
            sessionId,
            agentEndpointUrl,
            images: context.images,
            attachmentPaths: context.attachmentPaths,
            projectMcpTags: parseProjectMcpTags(claim.payload),
          },
        };
        logModelOverride(liveJob, roundJob, cardId);
        logClaimedCard(claim.payload);
        workerLog("Worker 正在实施当前卡片");

        const agentResult = await dependencies.runAgent(roundJob, cancellation);
        if (cancellation?.isSkipRequested || agentResult.error === "已跳过") {
          cancellation?.clearSkipRequest();
          await mcp.callJson("dispatch_skip_agent_session", {
            workerToken: job.workerToken,
            sessionId,
            reason: "用户请求跳过当前卡片",
          });
          terminalRecorded = true;
          const afterSkip = dependencies.inspectGit(job.cwd);
          if (!allowDirtyWorkspace) {
            if (afterSkip.kind === "dirty") {
              return {
                ok: false,
                error: `跳过后工作区不干净，停止批次：\n${afterSkip.output}`,
                processedCards,
              };
            }
            if (afterSkip.kind === "unknown") {
              return {
                ok: false,
                error: `跳过后无法判断工作区状态：${afterSkip.output}`,
                processedCards,
              };
            }
          }
          continue;
        }
        if (cancellation?.isCancelled || agentResult.error === "已取消") {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            "用户取消当前 Agent 会话",
            true,
          );
          terminalRecorded = true;
          return cancelledResult();
        }
        if (!agentResult.ok) {
          await mcp.callJson("dispatch_fail_agent_session", {
            workerToken: job.workerToken,
            sessionId,
            reason: agentResult.error ?? "Agent 会话失败",
          });
          terminalRecorded = true;
          return {
            ok: false,
            error: agentResult.error ?? `第 ${index} 次 Agent 会话失败`,
            processedCards,
          };
        }
        postAgent = true;

        const status = await mcp.callJson("dispatch_agent_session_status", {
          workerToken: job.workerToken,
        });
        assertSessionMatches(status, sessionId, cardId);
        const projectId = String(
          status.projectId ?? claim.payload.projectId ?? job.projectId ?? "",
        ).trim();
        const latest = await mcp.callJson("get_card", {
          cardId,
          ...(projectId ? { projectId } : {}),
        });
        const state = cardState(latest);
        const pending = asRecord(status.pending);

        if (state === "blocked") {
          return {
            ok: false,
            error: `卡片 ${cardId} 已进入阻塞中，Worker 停止批次`,
            processedCards,
          };
        }
        if (state === "verify" && pending == null) {
          processedCards += 1;
          workerLog(`咨询卡 ${cardId} 已送交验证`, "worker", "success");
          continue;
        }
        if (!pending || pending.status !== "declared") {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            `实施卡 ${cardId} 未声明 ready_to_submit`,
          );
          terminalRecorded = true;
          return {
            ok: false,
            error: `实施卡 ${cardId} 未声明 ready_to_submit`,
            processedCards,
          };
        }

        workerLog("Worker 正在提交当前卡片");
        const finalized = await validateAndFinalize(
          mcp,
          job,
          pending,
        );
        if (!finalized.ok) {
          if (!finalized.preservePending && !terminalRecorded) {
            await recordRoundFailure(
              mcp,
              job,
              sessionId,
              finalized.error ?? "Worker 收尾失败",
            );
            terminalRecorded = true;
          }
          return { ...finalized, processedCards };
        }
        terminalRecorded = true;
        processedCards += 1;
        workerLog(`卡片 ${cardId} 已验证、提交并送交人工验证`, "worker", "success");
        if (cancellation?.shouldStopAfterCurrentSession) {
          return cancellation.isCancelled ? cancelledResult() : drainedResult();
        }
      } catch (error) {
        const reason = error instanceof WorkerCancelledError
          ? "用户取消当前 Agent 会话"
          : `${postAgent ? "Worker 收尾失败" : "Agent 会话异常"}：${error instanceof Error ? error.message : String(error)}`;
        if (!terminalRecorded) {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            reason,
            error instanceof WorkerCancelledError,
          );
        }
        const tree = dependencies.inspectGit(job.cwd);
        const dirtySuffix = allowDirtyWorkspace || postAgent
          ? ""
          : tree.kind === "dirty"
          ? `\n工作区不干净，停止批次：\n${tree.output}`
          : tree.kind === "unknown"
          ? `\n无法判断工作区状态，停止批次：${tree.output}`
          : "";
        return error instanceof WorkerCancelledError
          ? cancelledResult()
          : { ok: false, error: `${reason}${dirtySuffix}`, processedCards };
      } finally {
        context?.cleanup();
        await scoped?.close().catch(() => undefined);
        await mcp.callJson("dispatch_close_agent_session", {
          workerToken: job.workerToken,
        }).catch(() => undefined);
      }
    }
    return completedResult(processedCards, "已达到批次上限");
  } catch (error) {
    if (error instanceof WorkerCancelledError) return cancelledResult();
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message, processedCards };
  } finally {
    await mcp.close().catch(() => undefined);
    workerLog("Worker 已关闭完整看板 MCP 连接");
  }
}

async function recoverPendingSessions(
  mcp: KanbanMcpConnection,
  job: DispatchJob,
): Promise<DispatchResult> {
  const listed = await mcp.callJson("dispatch_list_pending", {
    workerToken: job.workerToken,
  });
  const pending = Array.isArray(listed.pending) ? listed.pending : [];
  let processedCards = 0;
  for (const raw of pending) {
    const record = asRecord(raw);
    if (!record) continue;
    const sessionId = requiredString(record, "sessionId");
    const recovered = await mcp.callJson("dispatch_recover", {
      workerToken: job.workerToken,
      sessionId,
    });
    const result = await validateAndFinalize(
      mcp,
      job,
      recovered,
    );
    if (!result.ok) return { ...result, processedCards };
    processedCards += 1;
    workerLog(`已恢复 pending 会话 ${sessionId}`, "worker", "success");
  }
  return { ok: true, processedCards };
}

async function validateAndFinalize(
  mcp: KanbanMcpConnection,
  job: DispatchJob,
  pending: Record<string, unknown>,
): Promise<DispatchResult> {
  const sessionId = requiredString(pending, "sessionId");
  const cardId = requiredString(pending, "cardId");
  let status = String(pending.status ?? "");
  if (status === "declared") {
    workerLog("验证已由 Agent 会话完成，Worker 不再复跑测试");
    const recorded = await mcp.callJson("dispatch_record_validation_results", {
      workerToken: job.workerToken,
      sessionId,
      results: [],
    });
    status = String(recorded.status ?? "");
    if (status === "failed") {
      const reason = String(recorded.error ?? "验证失败");
      await mcp.callJson("dispatch_block_agent_session", {
        workerToken: job.workerToken,
        sessionId,
        reason,
      });
      return { ok: false, error: reason };
    }
  }
  if (!["validated", "committing", "committed", "finalized"].includes(status)) {
    return { ok: false, error: `pending 状态无法恢复：${status || "未知"}` };
  }
  workerLog("Worker 正在提交并送交验证");
  const finalized = await mcp.callJson("dispatch_finalize", {
    workerToken: job.workerToken,
    sessionId,
  });
  if (finalized.preservePending === true) {
    return {
      ok: false,
      preservePending: true,
      error: String(
        finalized.error ?? "Git 提交后工作区不干净，拒绝更新看板",
      ),
    };
  }
  if (
    finalized.status !== "finalized" ||
    String(finalized.sessionId ?? "") !== sessionId ||
    String(finalized.cardId ?? "") !== cardId
  ) {
    return { ok: false, error: `dispatch_finalize 返回状态不一致：${sessionId}` };
  }
  return { ok: true };
}

async function recordRoundFailure(
  mcp: KanbanMcpConnection,
  job: DispatchJob,
  sessionId: string,
  reason: string,
  block = false,
): Promise<void> {
  await mcp.callJson(
    block ? "dispatch_block_agent_session" : "dispatch_fail_agent_session",
    {
      workerToken: job.workerToken,
      sessionId,
      reason,
    },
  ).catch((error) => {
    workerLog(
      `记录会话失败状态失败：${error instanceof Error ? error.message : String(error)}`,
      "worker",
      "warning",
    );
  });
}

function assertSessionMatches(
  status: Record<string, unknown>,
  sessionId: string,
  cardId: string,
): void {
  if (
    status.sessionOpen !== true ||
    status.pickClaimed !== true ||
    String(status.sessionId ?? "") !== sessionId ||
    String(status.cardId ?? "") !== cardId
  ) {
    throw new Error(`Agent 会话状态与 claim 不一致：${sessionId}/${cardId}`);
  }
}

function cardState(card: Record<string, unknown>): "verify" | "blocked" | "active" {
  const columnId = String(card.columnId ?? "");
  const columnName = String(card.columnName ?? "");
  if (columnId === "verify" || columnName === "待验证") return "verify";
  if (columnId === "blocked" || columnName === "阻塞中") return "blocked";
  return "active";
}

function gitPreflightError(tree: GitWorkingTree): string | undefined {
  if (tree.kind === "dirty") {
    return `工作区不干净，未领取卡片：\n${tree.output}`;
  }
  if (tree.kind === "unknown") {
    return `无法判断 Git 工作区，未领取卡片：${tree.output}`;
  }
  return undefined;
}

function requiredString(
  record: Record<string, unknown>,
  key: string,
): string {
  const value = String(record[key] ?? "").trim();
  if (!value) throw new Error(`协议字段 ${key} 不能为空`);
  return value;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function completedResult(
  processedCards: number,
  reason: string,
): DispatchResult {
  workerLog(`Worker 批次完成：${reason}；已处理 ${processedCards} 张`, "worker", "success");
  return {
    ok: true,
    summary: `Worker 批次完成：${reason}；已处理 ${processedCards} 张`,
    processedCards,
  };
}

function logClaimedCard(payload: Record<string, unknown>): void {
  const items = Array.isArray(payload.workItems) ? payload.workItems : [];
  let title = "";
  const details: string[] = [];
  for (const raw of items) {
    const record = asRecord(raw);
    if (!record) continue;
    const kind = String(record.kind ?? "");
    const text = String(record.text ?? "").trim();
    if (!text) continue;
    if (kind === "title" && !title) title = text;
    else details.push(text);
  }
  workerLog(`当前卡片：${title || String(payload.cardId ?? "未命名卡片")}`);
  if (details.length > 0) {
    const detail = details.join("\n").slice(0, 800);
    workerLog(`当前任务：${detail}`);
  }
}

function readLiveJob(job: DispatchJob): DispatchJob {
  if (!job.liveFile) return job;
  try {
    const raw = JSON.parse(readFileSync(job.liveFile, "utf8")) as Partial<DispatchJob>;
    return applyLiveJobOverlay(job, raw);
  } catch {
    return job;
  }
}

function logModelOverride(
  original: DispatchJob,
  round: RoundDispatchJob,
  cardId: string,
): void {
  if (
    round.engine === original.engine &&
    round.model === original.model &&
    JSON.stringify(round.modelParams ?? []) ===
      JSON.stringify(original.modelParams ?? [])
  ) {
    return;
  }
  workerLog(
    `本卡覆盖：engine=${round.engine} model=${round.model ?? "(平台默认)"} params=${JSON.stringify(round.modelParams ?? [])} cardId=${cardId}`,
  );
}
