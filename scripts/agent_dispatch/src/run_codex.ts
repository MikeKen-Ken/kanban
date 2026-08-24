import { spawn, type ChildProcess } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { WorkerCancellation } from "./cancellation.ts";
import {
  createCodexLogState,
  createLineBuffer,
  recordsFromCodexJsonLine,
  recordsFromCodexStderrLine,
} from "./codex_exec_log.ts";
import { createCodexAgentHome, resolveUserCodexHome } from "./codex_mcp.ts";
import {
  effortToCodexConfigArgs,
  type DispatchResult,
  type RoundDispatchJob,
} from "./types.ts";
import { isRetryableError } from "./retry.ts";
import {
  startPollingDispatchTerminal,
} from "./dispatch_terminal.ts";
import {
  emitAssistantMessage,
  emitConversationSnapshot,
  emitSessionStart,
  emitThinkingMessage,
  sessionStartText,
} from "./interaction_bridge.ts";
import {
  extractCodexAssistantEventText,
  extractCodexTranscriptMessage,
  type ConversationTranscriptMessage,
} from "./assistant_text.ts";
import { buildConversationTranscript } from "./conversation_transcript.ts";
import { buildCodexProcessEnv } from "./codex_windows_env.ts";
import { workerLog, workerLogRecords } from "./worker_log.ts";

export function resolveCodexCommand(): {
  command: string;
  prefixArgs: string[];
  shell: boolean;
} {
  const packageRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
  const bundledCli = join(
    packageRoot,
    "node_modules",
    "@openai",
    "codex",
    "bin",
    "codex.js",
  );
  if (existsSync(bundledCli)) {
    return {
      command: process.execPath,
      prefixArgs: [bundledCli],
      shell: false,
    };
  }
  return {
    command: "codex",
    prefixArgs: [],
    shell: process.platform === "win32",
  };
}

/**
 * Codex 0.147 已移除 `exec --full-auto`。
 * `--approve-for-me` 会走 workspace-write 沙箱并自动审批，不能再叠加 `--sandbox`。
 * `--json` 把会话事件打到 stdout，避免把 TTY 回放误当成 stderr 警告。
 */
export function buildCodexExecArgs(options: {
  cwd: string;
  lastMessageFile: string;
  extraConfigArgs?: string[];
  model?: string;
  enableSandbox?: boolean;
}): string[] {
  const args = ["exec", "--json"];
  // `enableSandbox` is shared by both engines. `--approve-for-me` always
  // selects Codex's workspace-write sandbox, so it cannot represent a disabled
  // setting. The Worker is the explicit unattended execution boundary.
  if (options.enableSandbox === true) {
    args.push("--approve-for-me");
  } else {
    args.push("--dangerously-bypass-approvals-and-sandbox");
  }
  args.push(
    "--skip-git-repo-check",
    "--cd",
    options.cwd,
    "-o",
    options.lastMessageFile,
    ...(options.extraConfigArgs ?? []),
  );
  if (process.platform === "win32" && options.enableSandbox === true) {
    // MSIX 版 pwsh 无法被 elevated sandbox 的受限令牌启动（CreateProcessAsUserW）。
    args.push("-c", 'windows.sandbox="unelevated"');
  }
  if (options.model?.trim()) {
    args.push("-m", options.model.trim());
  }
  args.push("-");
  return args;
}

export async function runCodex(
  job: RoundDispatchJob,
  cancellation?: WorkerCancellation,
): Promise<DispatchResult> {
  const startedAt = Date.now();
  const mcpUrl = job.round.agentEndpointUrl.trim();
  if (!mcpUrl) {
    return { ok: false, error: "This claim is missing a scoped MCP endpoint" };
  }

  const temp = mkdtempSync(join(tmpdir(), "kanban-codex-"));
  const promptFile = join(temp, "prompt.txt");
  const lastMessageFile = join(temp, "last.txt");
  try {
    writeFileSync(promptFile, job.prompt, "utf8");
    const agentHome = createCodexAgentHome({
      mcpUrl,
      userCodexHome: resolveUserCodexHome(),
      projectMcpTags: job.round.projectMcpTags,
      tempRoot: temp,
    });
    workerLog(
      `Codex uses an isolated CODEX_HOME, copied user AGENTS.md (Architecture pre-read is covered) and skills; ` +
        `merged user MCP servers (${agentHome.mcpServerNames.join(", ") || "none"}); ` +
        `kanbanMCP is forced to scoped (${mcpUrl})`,
    );

    const args = buildCodexExecArgs({
      cwd: job.cwd,
      lastMessageFile,
      extraConfigArgs: effortToCodexConfigArgs(job),
      model: job.model,
      enableSandbox: job.enableSandbox,
    });

    workerLog(`Codex args=${args.join(" ")}`);
    emitSessionStart(job);
    const live: ConversationTranscriptMessage[] = [];
    const sessionUser = sessionStartText(job);
    if (sessionUser) live.push({ role: "user", text: sessionUser });
    const fromTurns: ConversationTranscriptMessage[] = [];
    let endedByTerminal = false;
    const stopAfterTerminal = (reason: string): void => {
      if (endedByTerminal) return;
      endedByTerminal = true;
      workerLog(`Finalization tool succeeded (${reason}); ending Codex session`);
    };

    const emittedAssistant = new Set<string>();
    const emittedThinking = new Set<string>();
    const emitAssistant = (text: string): void => {
      const normalized = text.trim();
      if (!normalized || emittedAssistant.has(normalized)) return;
      emittedAssistant.add(normalized);
      live.push({ role: "assistant", text: normalized });
      emitAssistantMessage(job, normalized);
    };
    const emitThinking = (text: string): void => {
      const normalized = text.trim();
      if (!normalized || emittedThinking.has(normalized)) return;
      emittedThinking.add(normalized);
      live.push({ role: "thinking", text: normalized });
      emitThinkingMessage(job, normalized);
    };

    const code = await new Promise<number>((resolvePromise, reject) => {
      const codex = resolveCodexCommand();
      let child: ChildProcess | undefined;
      const killChild = (): void => {
        if (!child || child.killed) return;
        try {
          if (process.platform === "win32") {
            spawn("taskkill", ["/PID", String(child.pid), "/T", "/F"], {
              shell: true,
            });
          } else {
            child.kill("SIGTERM");
          }
        } catch {
          // 子进程可能已在取消边界退出。
        }
      };
      cancellation?.onCancel(killChild);
      const terminalPoll = job.terminateAfterDispatchTerminal === false
        ? { stop() {} }
        : startPollingDispatchTerminal(
          job.round.peekDispatchTerminal,
          (kind) => {
            stopAfterTerminal(`MCP ${kind}`);
            killChild();
          },
        );
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        terminalPoll.stop();
        resolvePromise(130);
        return;
      }
      const logState = createCodexLogState();
      const stdoutLines = createLineBuffer((line) => {
        workerLogRecords(recordsFromCodexJsonLine(line, logState));
        try {
          const parsed = JSON.parse(line);
          const message = extractCodexTranscriptMessage(parsed);
          if (message) fromTurns.push(message);
          if (message?.role === "thinking") emitThinking(message.text);
          emitAssistant(extractCodexAssistantEventText(parsed));
        } catch {
          // 非 JSON 行只记日志。
        }
      });
      const stderrLines = createLineBuffer((line) => {
        workerLogRecords(recordsFromCodexStderrLine(line, logState));
      });
      child = spawn(codex.command, [...codex.prefixArgs, ...args], {
        cwd: job.cwd,
        env: {
          ...buildCodexProcessEnv(),
          CODEX_HOME: agentHome.home,
        },
        stdio: ["pipe", "pipe", "pipe"],
        shell: codex.shell,
      });
      child.stdout?.on("data", (buf: Buffer) => {
        stdoutLines.push(buf);
      });
      child.stderr?.on("data", (buf: Buffer) => {
        stderrLines.push(buf);
      });
      child.on("error", (err) => {
        terminalPoll.stop();
        reject(err);
      });
      if (!child.stdin) {
        terminalPoll.stop();
        reject(new Error("Codex stdin is unavailable"));
        return;
      }
      child.stdin.write(readFileSync(promptFile));
      child.stdin.end();
      child.on("close", (exitCode) => {
        stdoutLines.flush();
        stderrLines.flush();
        terminalPoll.stop();
        if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
          resolvePromise(130);
          return;
        }
        resolvePromise(endedByTerminal ? 0 : (exitCode ?? 1));
      });
    });

    if (cancellation?.isSkipRequested) {
      workerLog(`Codex exec skipped elapsedMs=${Date.now() - startedAt}`);
      return { ok: false, error: "Skipped" };
    }
    if (cancellation?.isCancelled) {
      workerLog(`Codex exec cancelled elapsedMs=${Date.now() - startedAt}`);
      return { ok: false, error: "Cancelled" };
    }

    let summary: string | undefined;
    try {
      summary = readFileSync(lastMessageFile, "utf8").trim();
    } catch {
      summary = undefined;
    }

    workerLog(`Codex exec exitCode=${code} elapsedMs=${Date.now() - startedAt}`);
    if (summary) emitAssistant(summary);
    emitConversationSnapshot(
      job,
      buildConversationTranscript({
        sessionUser,
        live,
        fromTurns,
        trailingAssistant: summary,
      }),
    );
    if (code === 0) {
      return { ok: true, summary: summary || "Codex session completed" };
    }
    return {
      ok: false,
      error: `Codex exited with code ${code}`,
      summary,
      retryable: isRetryableError(summary),
    };
  } catch (error) {
    if (cancellation?.isSkipRequested) {
      return { ok: false, error: "Skipped" };
    }
    if (cancellation?.isCancelled) {
      return { ok: false, error: "Cancelled" };
    }
    return {
      ok: false,
      error: `Codex session error: ${error instanceof Error ? error.message : String(error)}`,
      retryable: isRetryableError(error),
    };
  } finally {
    try {
      rmSync(temp, { recursive: true, force: true });
    } catch {
      // 临时目录可能已由进程清理。
    }
  }
}
