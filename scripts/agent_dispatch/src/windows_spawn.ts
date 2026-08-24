import { spawn, type ChildProcess, type SpawnOptions } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { delimiter, extname, join } from "node:path";

const WINDOWS_BATCH_EXTS = new Set([".bat", ".cmd"]);

/** \u4E0D\u7ECF\u8FC7 shell \u5C55\u5F00\u53C2\u6570；Windows \u4E0A\u7684 .bat/.cmd \u8D70 cmd.exe，\u907F\u514D ENOENT/EINVAL。 */
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

/** \u5E38\u89C1 Flutter \u5B89\u88C5\u4F4D\u7F6E\u4F18\u5148\u4E8E PATH，\u907F\u514D\u684C\u9762\u8FDB\u7A0B PATH \u91CC\u6CA1\u6709 Flutter。 */
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
