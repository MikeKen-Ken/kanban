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
import { createCodexAgentHome, resolveUserCodexHome } from "./codex_mcp.ts";
import {
  effortToCodexConfigArgs,
  type DispatchResult,
  type RoundDispatchJob,
} from "./types.ts";

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
 */
export function buildCodexExecArgs(options: {
  cwd: string;
  lastMessageFile: string;
  extraConfigArgs?: string[];
  model?: string;
}): string[] {
  const args = [
    "exec",
    "--approve-for-me",
    "--skip-git-repo-check",
    "--cd",
    options.cwd,
    "-o",
    options.lastMessageFile,
    ...(options.extraConfigArgs ?? []),
  ];
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
    return { ok: false, error: "本轮 claim 缺少 scoped MCP 端点" };
  }

  const temp = mkdtempSync(join(tmpdir(), "kanban-codex-"));
  const promptFile = join(temp, "prompt.txt");
  const lastMessageFile = join(temp, "last.txt");
  try {
    writeFileSync(promptFile, job.prompt, "utf8");
    const agentHome = createCodexAgentHome({
      mcpUrl,
      userCodexHome: resolveUserCodexHome(),
      tempRoot: temp,
    });
    console.log(
      `Codex 使用隔离 CODEX_HOME，仅注入精简看板 MCP（${mcpUrl}）`,
    );

    const args = buildCodexExecArgs({
      cwd: job.cwd,
      lastMessageFile,
      extraConfigArgs: effortToCodexConfigArgs(job),
      model: job.model,
    });

    console.log(`Codex args=${args.join(" ")}`);

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
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        resolvePromise(130);
        return;
      }
      child = spawn(codex.command, [...codex.prefixArgs, ...args], {
        cwd: job.cwd,
        env: { ...process.env, CODEX_HOME: agentHome.home },
        stdio: ["pipe", "pipe", "pipe"],
        shell: codex.shell,
      });
      child.stdout?.on("data", (buf: Buffer) => {
        process.stdout.write(buf);
      });
      child.stderr?.on("data", (buf: Buffer) => {
        process.stderr.write(buf);
      });
      child.on("error", reject);
      if (!child.stdin) {
        reject(new Error("Codex stdin 不可用"));
        return;
      }
      child.stdin.write(readFileSync(promptFile));
      child.stdin.end();
      child.on("close", (exitCode) => {
        if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
          resolvePromise(130);
          return;
        }
        resolvePromise(exitCode ?? 1);
      });
    });

    if (cancellation?.isSkipRequested) {
      console.log(`Codex exec skipped elapsedMs=${Date.now() - startedAt}`);
      return { ok: false, error: "已跳过" };
    }
    if (cancellation?.isCancelled) {
      console.log(`Codex exec cancelled elapsedMs=${Date.now() - startedAt}`);
      return { ok: false, error: "已取消" };
    }

    let summary: string | undefined;
    try {
      summary = readFileSync(lastMessageFile, "utf8").trim();
    } catch {
      summary = undefined;
    }

    console.log(`Codex exec exitCode=${code} elapsedMs=${Date.now() - startedAt}`);
    if (code === 0) {
      return { ok: true, summary: summary || "Codex 会话完成" };
    }
    return { ok: false, error: `Codex 退出码 ${code}`, summary };
  } finally {
    try {
      rmSync(temp, { recursive: true, force: true });
    } catch {
      // 临时目录可能已由进程清理。
    }
  }
}
