import { spawn, type ChildProcess, type SpawnOptions } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { delimiter, extname, join } from "node:path";

const WINDOWS_BATCH_EXTS = new Set([".bat", ".cmd"]);

/** 不经过 shell 展开参数；Windows 上的 .bat/.cmd 走 cmd.exe，避免 ENOENT/EINVAL。 */
export function spawnUnexpanded(
  command: string,
  args: readonly string[],
  options: SpawnOptions,
): ChildProcess {
  if (process.platform !== "win32") {
    return spawn(command, args, { ...options, shell: false });
  }
  const resolved = resolveWindowsExecutable(command, envFrom(options));
  if (resolved && isWindowsBatchFile(resolved)) {
    const invocation = buildWindowsCmdInvocation(resolved, args);
    return spawn(invocation.command, invocation.args, {
      ...options,
      shell: false,
      windowsVerbatimArguments: true,
    });
  }
  return spawn(resolved ?? command, args, { ...options, shell: false });
}

export function resolveWindowsExecutable(
  command: string,
  env: NodeJS.ProcessEnv = process.env,
): string | undefined {
  const trimmed = command.trim();
  if (!trimmed) return undefined;
  if (hasPathSeparator(trimmed)) {
    return resolveWithPathext(trimmed, env);
  }
  const pathValue = env.Path ?? env.PATH ?? "";
  const dirs = [
    ...flutterSdkBinDirs(env),
    ...pathValue.split(delimiter),
  ];
  for (const dir of dirs) {
    if (!dir.trim()) continue;
    const found = resolveWithPathext(join(dir, trimmed), env);
    if (found) return found;
  }
  return undefined;
}

/** 常见 Flutter 安装位置优先于 PATH，避免桌面进程 PATH 里没有 Flutter。 */
export function flutterSdkBinDirs(env: NodeJS.ProcessEnv = process.env): string[] {
  const dirs: string[] = [];
  const root = (env.FLUTTER_ROOT ?? "").trim();
  if (root) dirs.push(join(root, "bin"));
  const localAppData = (env.LOCALAPPDATA ?? "").trim();
  if (localAppData) dirs.push(join(localAppData, "flutter", "bin"));
  const home = (env.USERPROFILE ?? env.HOME ?? "").trim();
  if (home) {
    dirs.push(join(home, "flutter", "bin"));
    dirs.push(join(home, "fvm", "default", "bin"));
  }
  return dirs;
}

export function buildWindowsCmdInvocation(
  executable: string,
  args: readonly string[],
): { command: string; args: string[] } {
  const inner = [quoteCmdArg(executable), ...args.map(quoteCmdArg)].join(" ");
  return {
    command: process.env.ComSpec || "cmd.exe",
    args: ["/d", "/s", "/v:off", "/c", `"${inner}"`],
  };
}

export function quoteCmdArg(value: string): string {
  return `"${value.replace(/%/g, "%%").replace(/"/g, '""')}"`;
}

function isWindowsBatchFile(file: string): boolean {
  return WINDOWS_BATCH_EXTS.has(extname(file).toLowerCase());
}

function hasPathSeparator(command: string): boolean {
  return command.includes("/") || command.includes("\\") || /^[A-Za-z]:/.test(command);
}

function resolveWithPathext(
  base: string,
  env: NodeJS.ProcessEnv,
): string | undefined {
  const ext = extname(base);
  if (ext) return isExistingFile(base) ? base : undefined;
  const pathext = env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD";
  for (const item of pathext.split(";")) {
    const suffix = item.trim();
    if (!suffix) continue;
    const candidate = base + suffix;
    if (isExistingFile(candidate)) return candidate;
  }
  return undefined;
}

function isExistingFile(path: string): boolean {
  try {
    return existsSync(path) && statSync(path).isFile();
  } catch {
    return false;
  }
}

function envFrom(options: SpawnOptions): NodeJS.ProcessEnv {
  if (options.env && typeof options.env === "object") {
    return options.env as NodeJS.ProcessEnv;
  }
  return process.env;
}
