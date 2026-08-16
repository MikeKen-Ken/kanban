import { spawn } from "node:child_process";
import { isAbsolute, relative, resolve, sep } from "node:path";

export const DEFAULT_VERIFICATION_TIMEOUT_MS = 10 * 60_000;
export const MAX_VERIFICATION_TIMEOUT_MS = 15 * 60_000;
const MAX_OUTPUT_CHARS = 16_000;

export type VerificationCommand = {
  executable: string;
  args: string[];
  cwd?: string;
  expectedExitCode?: number;
  timeoutMs?: number;
};

export type VerificationResult = {
  commandSummary: string;
  executable: string;
  args: string[];
  cwd: string;
  exitCode: number;
  durationMs: number;
  output: string;
  timedOut: boolean;
  passed: boolean;
};

export async function runVerificationCommand(
  item: VerificationCommand,
  repoRoot: string,
): Promise<VerificationResult> {
  const startedAt = Date.now();
  const timeoutMs = clampTimeout(item.timeoutMs);
  const expectedExitCode = Number.isInteger(item.expectedExitCode)
    ? item.expectedExitCode!
    : 0;
  const commandCwd = item.cwd?.trim() || ".";
  const commandSummary = summarizeCommand(item.executable, item.args);
  let resolvedCwd: string;
  try {
    resolvedCwd = resolveCommandCwd(repoRoot, commandCwd);
  } catch (error) {
    return {
      commandSummary,
      executable: item.executable,
      args: [...item.args],
      cwd: commandCwd,
      exitCode: -1,
      durationMs: Date.now() - startedAt,
      output: error instanceof Error ? error.message : String(error),
      timedOut: false,
      passed: false,
    };
  }

  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let settled = false;
    const child = spawn(item.executable, item.args, {
      cwd: resolvedCwd,
      shell: false,
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    child.stdout?.on("data", (chunk: Buffer | string) => {
      stdout = appendTruncated(stdout, String(chunk));
    });
    child.stderr?.on("data", (chunk: Buffer | string) => {
      stderr = appendTruncated(stderr, String(chunk));
    });

    const finish = (exitCode: number): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(killGrace);
      const output = combineOutput(stdout, stderr);
      resolve({
        commandSummary,
        executable: item.executable,
        args: [...item.args],
        cwd: commandCwd,
        exitCode,
        durationMs: Date.now() - startedAt,
        output,
        timedOut,
        passed: !timedOut && exitCode === expectedExitCode,
      });
    };

    child.on("error", (error) => {
      stderr = appendTruncated(stderr, error.message);
      finish(-1);
    });
    child.on("close", (code) => finish(timedOut ? 124 : (code ?? -1)));

    let killGrace: NodeJS.Timeout | undefined;
    const timer = setTimeout(() => {
      timedOut = true;
      terminateProcessTree(child.pid);
      killGrace = setTimeout(() => finish(124), 3_000);
      killGrace.unref?.();
    }, timeoutMs);
    timer.unref?.();
  });
}

export async function runVerificationCommands(
  commands: VerificationCommand[],
  cwd: string,
): Promise<VerificationResult[]> {
  const results: VerificationResult[] = [];
  for (const command of commands) {
    const result = await runVerificationCommand(command, cwd);
    results.push(result);
    if (!result.passed) break;
  }
  return results;
}

export function clampTimeout(value: number | undefined): number {
  if (!Number.isFinite(value)) return DEFAULT_VERIFICATION_TIMEOUT_MS;
  return Math.max(100, Math.min(MAX_VERIFICATION_TIMEOUT_MS, Math.trunc(value!)));
}

function appendTruncated(current: string, next: string): string {
  const combined = current + next;
  if (combined.length <= MAX_OUTPUT_CHARS) return combined;
  return `…（前文已截断）${combined.slice(-MAX_OUTPUT_CHARS)}`;
}

function combineOutput(stdout: string, stderr: string): string {
  const out = stdout.trim();
  const err = stderr.trim();
  if (!out) return err;
  if (!err) return out;
  return `stdout:\n${out}\n\nstderr:\n${err}`;
}

function terminateProcessTree(pid: number | undefined): void {
  if (!pid) return;
  try {
    if (process.platform === "win32") {
      const killer = spawn("taskkill", ["/PID", String(pid), "/T", "/F"], {
        windowsHide: true,
        stdio: "ignore",
      });
      killer.unref();
    } else {
      process.kill(pid, "SIGTERM");
    }
  } catch {
    // 进程可能已在超时边界退出。
  }
}

export function resolveCommandCwd(repoRoot: string, cwd: string): string {
  const root = resolve(repoRoot);
  if (isAbsolute(cwd)) {
    throw new Error(`验证 cwd 必须是仓库内相对路径：${cwd}`);
  }
  const target = resolve(root, cwd);
  const relation = relative(root, target);
  if (relation === ".." ||
      relation.startsWith(`..${sep}`) ||
      isAbsolute(relation)) {
    throw new Error(`验证 cwd 逃出仓库：${cwd}`);
  }
  return target;
}

function summarizeCommand(executable: string, args: string[]): string {
  return [executable, ...args]
    .map((part) => /\s|"/.test(part) ? JSON.stringify(part) : part)
    .join(" ");
}
