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
import { toShellSpanReportPayload } from "./cursor_shell_spans.ts";
import { runCodex } from "./run_codex.ts";
import { runCursor } from "./run_cursor.ts";
import { runAgentWithRetry } from "./run_agent_with_retry.ts";
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
    requireTests?: boolean;
  }): SessionContext;
  runAgent(
    job: RoundDispatchJob,
    cancellation?: WorkerCancellation,
  ): Promise<DispatchResult>;
  sleep?: (ms: number) => Promise<void>;
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
  workerLog(`Worker batch started: endpoint=${job.mcpEndpoint} limit=${limit}`);
  workerLog(
    `Injected user rules: ${userRules.count}, ${userRules.bytes} bytes; user skills are not written to the prompt`,
  );

  const cancelledResult = (): DispatchResult => ({
    ok: false,
    error: "Cancelled",
    processedCards,
  });
  const drainedResult = (): DispatchResult => ({
    ok: true,
    summary: `Stopped after the current session; processed ${processedCards} card(s)`,
    processedCards,
  });

  try {
    workerLog("Worker connected to the full Kanban MCP; recovering unfinished finalization");
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
      const peek = await mcp.callJson("peek_next_card", {
        ...(liveJob.projectId ? { projectId: liveJob.projectId } : {}),
      });
      if (peek.found !== true) {
        return completedResult(processedCards, "No more cards available");
      }

      const preview = mergeJobWithCardOverrides(liveJob, peek);
      const tree = dependencies.inspectGit(job.cwd);
      if (tree.kind === "dirty" && preview.allowDirtyWorkspace === true) {
        workerLog(`Dirty workspace allowed; continuing claim:\n${tree.output}`);
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
        return completedResult(processedCards, "Queue became empty during claim");
      }

      const roundLabel = limit >= 999 ? `${index}` : `${index}/${limit}`;
      workerLog(`──────── Worker card round ${roundLabel} ────────`);

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
            `Scoped MCP tool gate failed: actual=${tools.join(",")}, expected=${DISPATCH_SCOPED_TOOL_NAMES.join(",")}`,
          );
        }

        const overridden = mergeJobWithCardOverrides(liveJob, claim.payload);
        context = dependencies.createContext({
          basePrompt: job.prompt,
          architecture,
          userRules: userRules.text,
          claim,
          requireTests: overridden.requireTests !== false,
        });
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
            cardContext: claim.payload,
            projectMcpTags: parseProjectMcpTags(claim.payload),
            reportShellSpan: async (span) => {
              await mcp.callJson(
                "dispatch_report_shell_span",
                toShellSpanReportPayload({
                  workerToken: job.workerToken,
                  sessionId,
                  span,
                }),
              );
            },
            peekDispatchTerminal: async () => {
              const status = await mcp.callJson("dispatch_agent_session_status", {
                workerToken: job.workerToken,
              });
              const pending = asRecord(status.pending);
              if (String(pending?.status ?? "") === "declared") {
                return "declared";
              }
              const projectId = String(
                status.projectId ?? claim.payload.projectId ?? job.projectId ?? "",
              ).trim();
              const latest = await mcp.callJson("get_card", {
                cardId,
                ...(projectId ? { projectId } : {}),
              });
              const state = cardState(latest);
              return state === "active" ? "none" : state;
            },
          },
        };
        logModelOverride(liveJob, roundJob, cardId);
        logClaimedCard(claim.payload);
        workerLog(`Tests for this card: ${roundJob.requireTests === false ? "not required" : "required"}`);
        workerLog("Worker is processing the current card");

        const agentResult = await runAgentWithRetry(
          dependencies.runAgent,
          roundJob,
          cancellation,
          dependencies.sleep,
        );
        if (cancellation?.isSkipRequested || agentResult.error === "Skipped") {
          cancellation?.clearSkipRequest();
          await mcp.callJson("dispatch_skip_agent_session", {
            workerToken: job.workerToken,
            sessionId,
            reason: "User requested skipping the current card",
          });
          terminalRecorded = true;
          const afterSkip = dependencies.inspectGit(job.cwd);
          if (!allowDirtyWorkspace) {
            if (afterSkip.kind === "dirty") {
              return {
                ok: false,
                error: `Workspace is dirty after skip; stopping batch:\n${afterSkip.output}`,
                processedCards,
              };
            }
            if (afterSkip.kind === "unknown") {
              return {
                ok: false,
                error: `Unable to determine workspace state after skip: ${afterSkip.output}`,
                processedCards,
              };
            }
          }
          continue;
        }
        if (cancellation?.isCancelled || agentResult.error === "Cancelled") {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            "User cancelled the current Agent session",
            true,
          );
          terminalRecorded = true;
          return cancelledResult();
        }
        if (!agentResult.ok) {
          await mcp.callJson("dispatch_fail_agent_session", {
            workerToken: job.workerToken,
            sessionId,
            reason: agentResult.error ?? "Agent session failed",
          });
          terminalRecorded = true;
          return {
            ok: false,
            error: agentResult.error ?? `Agent session ${index} failed`,
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
            error: `Card ${cardId} is blocked; Worker is stopping the batch`,
            processedCards,
          };
        }
        if (state === "verify" && pending == null) {
          processedCards += 1;
          workerLog(`Consultation card ${cardId} was submitted for verification`, "worker", "success");
          continue;
        }
        if (!pending || pending.status !== "declared") {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            `Card ${cardId} did not declare ready_to_submit`,
          );
          terminalRecorded = true;
          return {
            ok: false,
            error: `Card ${cardId} did not declare ready_to_submit`,
            processedCards,
          };
        }

        workerLog("Worker is finalizing the current card");
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
              finalized.error ?? "Worker finalization failed",
            );
            terminalRecorded = true;
          }
          return { ...finalized, processedCards };
        }
        terminalRecorded = true;
        processedCards += 1;
        workerLog(`Card ${cardId} was validated, committed, and submitted for manual verification`, "worker", "success");
        if (cancellation?.shouldStopAfterCurrentSession) {
          return cancellation.isCancelled ? cancelledResult() : drainedResult();
        }
      } catch (error) {
        const reason = error instanceof WorkerCancelledError
          ? "User cancelled the current Agent session"
          : `${postAgent ? "Worker finalization failed" : "Agent session error"}: ${error instanceof Error ? error.message : String(error)}`;
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
          ? `\nWorkspace is dirty; stopping batch:\n${tree.output}`
          : tree.kind === "unknown"
          ? `\nUnable to determine workspace state; stopping batch: ${tree.output}`
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
    return completedResult(processedCards, "Batch limit reached");
  } catch (error) {
    if (error instanceof WorkerCancelledError) return cancelledResult();
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message, processedCards };
  } finally {
    await mcp.close().catch(() => undefined);
    workerLog("Worker closed the full Kanban MCP connection");
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
    workerLog(`Recovered pending session ${sessionId}`, "worker", "success");
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
  workerLog("Validation was completed in the Agent session; Worker will not rerun tests");
    const recorded = await mcp.callJson("dispatch_record_validation_results", {
      workerToken: job.workerToken,
      sessionId,
      results: [],
    });
    status = String(recorded.status ?? "");
    if (status === "failed") {
      const reason = String(recorded.error ?? "Validation failed");
      await mcp.callJson("dispatch_block_agent_session", {
        workerToken: job.workerToken,
        sessionId,
        reason,
      });
      return { ok: false, error: reason };
    }
  }
  if (!["validated", "committing", "committed", "finalized"].includes(status)) {
    return { ok: false, error: `Cannot recover pending status: ${status || "unknown"}` };
  }
  workerLog("Worker is committing and submitting for verification");
  const finalized = await mcp.callJson("dispatch_finalize", {
    workerToken: job.workerToken,
    sessionId,
  });
  if (finalized.preservePending === true) {
    return {
      ok: false,
      preservePending: true,
      error: String(
        finalized.error ?? "Workspace is dirty after the Git commit; refusing to update the board",
      ),
    };
  }
  if (
    finalized.status !== "finalized" ||
    String(finalized.sessionId ?? "") !== sessionId ||
    String(finalized.cardId ?? "") !== cardId
  ) {
    return { ok: false, error: `dispatch_finalize returned an inconsistent status: ${sessionId}` };
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
      `Failed to record the session failure state: ${error instanceof Error ? error.message : String(error)}`,
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
    throw new Error(`Agent session status does not match the claim: ${sessionId}/${cardId}`);
  }
}

function cardState(card: Record<string, unknown>): "verify" | "blocked" | "active" {
  const columnId = String(card.columnId ?? "");
  const columnName = String(card.columnName ?? "");
  if (columnId === "verify" || columnName === "Verify" || columnName === "待验证") return "verify";
  if (columnId === "blocked" || columnName === "Blocked" || columnName === "阻塞中") return "blocked";
  return "active";
}

function gitPreflightError(tree: GitWorkingTree): string | undefined {
  if (tree.kind === "dirty") {
    return `Workspace is dirty; card was not claimed:\n${tree.output}`;
  }
  if (tree.kind === "unknown") {
    return `Unable to determine Git workspace state; card was not claimed: ${tree.output}`;
  }
  return undefined;
}

function requiredString(
  record: Record<string, unknown>,
  key: string,
): string {
  const value = String(record[key] ?? "").trim();
  if (!value) throw new Error(`Protocol field ${key} cannot be empty`);
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
  workerLog(`Worker batch completed: ${reason}; processed ${processedCards} card(s)`, "worker", "success");
  return {
    ok: true,
    summary: `Worker batch completed: ${reason}; processed ${processedCards} card(s)`,
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
  workerLog(`Current card: ${title || String(payload.cardId ?? "Untitled card")}`);
  if (details.length > 0) {
    const detail = details.join("\n").slice(0, 800);
    workerLog(`Current task: ${detail}`);
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
    `Card override: engine=${round.engine} model=${round.model ?? "(platform default)"} params=${JSON.stringify(round.modelParams ?? [])} cardId=${cardId}`,
  );
}
