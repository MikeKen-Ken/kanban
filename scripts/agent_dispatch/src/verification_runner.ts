import { spawn } from "node:child_process";
import { isAbsolute, relative, resolve, sep } from "node:path";
import { resolveWindowsExecutable, spawnUnexpanded } from "./windows_spawn.ts";

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
  const failedLaunch = (
    output: string,
  ): VerificationResult => ({
    commandSummary,
    executable: item.executable,
    args: [...item.args],
    cwd: commandCwd,
    exitCode: -1,
    durationMs: Date.now() - startedAt,
    output,
    timedOut: false,
    passed: false,
  });
  let resolvedCwd: string;
  try {
    resolvedCwd = resolveCommandCwd(repoRoot, commandCwd);
  } catch (error) {
    return failedLaunch(error instanceof Error ? error.message : String(error));
  }
  if (process.platform === "win32" &&
      !resolveWindowsExecutable(item.executable)) {
    return failedLaunch(describeMissingExecutable(item.executable));
  }

  return new Promise((resolvePromise) => {
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let settled = false;
    const spawnOptions = {
      cwd: resolvedCwd,
      shell: false,
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"] as ["ignore", "pipe", "pipe"],
    };
    let child;
    try {
      child = spawnUnexpanded(item.executable, item.args, spawnOptions);
    } catch (error) {
      resolvePromise(failedLaunch(describeLaunchError(item.executable, error)));
      return;
    }
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
      resolvePromise({
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
      stderr = appendTruncated(stderr, describeLaunchError(item.executable, error));
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

const SKIPPED_OUTPUT = "因前序验证失败未执行";

/// 将 fail-fast 截断的结果补齐为与声明命令等长，避免 MCP 因条数不一致拒收。
export function fillSkippedVerificationResults(
  commands: VerificationCommand[],
  results: VerificationResult[],
): VerificationResult[] {
  if (results.length >= commands.length) {
    return results.slice(0, commands.length);
  }
  const filled = results.slice();
  for (let index = results.length; index < commands.length; index += 1) {
    const command = commands[index]!;
    const cwd = command.cwd?.trim() || ".";
    filled.push({
      commandSummary: summarizeCommand(command.executable, command.args),
      executable: command.executable,
      args: [...command.args],
      cwd,
      exitCode: -1,
      durationMs: 0,
      output: SKIPPED_OUTPUT,
      timedOut: false,
      passed: false,
    });
  }
  return filled;
}

export function formatVerificationFailure(failed: VerificationResult): string {
  if (failed.timedOut) {
    return `验证命令超时：${failed.commandSummary}`;
  }
  const detail = pickFailureDetail(failed.output);
  const base = `验证命令失败（exitCode=${failed.exitCode}）：${failed.commandSummary}`;
  return detail ? `${base}；${detail}` : base;
}

function pickFailureDetail(output: string): string | undefined {
  const lines = output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !/^(stdout|stderr):$/i.test(line));
  if (lines.length === 0) return undefined;
  const summary = [...lines].reverse().find((line) =>
    /\d+\s+issues?\s+found/i.test(line) ||
    /error|failed|errno|enoent/i.test(line)
  );
  return summary ?? lines[0];
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

export function summarizeCommand(executable: string, args: string[]): string {
  return [executable, ...args]
    .map((part) => /\s|"/.test(part) ? JSON.stringify(part) : part)
    .join(" ");
}

export function describeMissingExecutable(executable: string): string {
  const name = executable.trim() || "(空)";
  return (
    `未找到可执行文件 ${name}（ENOENT）。` +
    `Worker 继承看板进程的 PATH；从开始菜单或快捷方式启动时，往往不含终端里才有的 Flutter。` +
    `请把 Flutter 的 bin 目录写入系统 PATH 后重启看板，或从已配置 PATH 的终端启动看板。`
  );
}

function describeLaunchError(executable: string, error: unknown): string {
  if (isExecutableNotFoundError(error)) {
    return describeMissingExecutable(executable);
  }
  return error instanceof Error ? error.message : String(error);
}

function isExecutableNotFoundError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  return (error as { code?: unknown }).code === "ENOENT";
}
