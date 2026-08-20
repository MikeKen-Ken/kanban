import { isAbsolute, relative, resolve } from "node:path";

/** Worker 注入：定位用定向 grep / 窄 glob，禁止仓库根无界列举。 */
export const DISPATCH_SEARCH_POLICY = `## 搜索范围（Worker）

定位代码时 MUST 用 grep 或带文件名/目录限定的 glob，并指定子目录。
MUST NOT 对仓库根做无界 glob（\`**\`、\`**/*\`、\`**/*.*\`）。
MUST NOT 把无界 glob 与 grep 并行；grep 已返回候选文件时直接读那些路径。
MUST NOT 把 glob 目标指到 \`.git\`、\`.svn\` 或 \`build\`。
卡片里的界面入口按产品表面落到功能目录：看板卡片详情（含文件附件三个点菜单）在 \`app/lib/features/kanban/\`；Agent 调度窗口本身才在 \`agent_dispatch/\`。不要把「工作台」默认理解成必须先搜调度目录。
`;

const UNBOUNDED_PATTERNS = new Set(["**", "**/*", "**/*.*", "**/**"]);

const EXCLUDED_GLOB_DIR_SEGMENTS = new Set([".git", ".svn", "build"]);

export function isUnboundedGlobPattern(pattern: string): boolean {
  const normalized = pattern.replaceAll("\\", "/").trim();
  if (!normalized) return true;
  if (UNBOUNDED_PATTERNS.has(normalized)) return true;
  return /^(?:\*\*\/)+\*$/.test(normalized);
}

export function resolveGlobTarget(cwd: string, targetDirectory?: string): string {
  const raw = targetDirectory?.trim() ?? "";
  if (!raw) return resolve(cwd);
  return isAbsolute(raw) ? resolve(raw) : resolve(cwd, raw);
}

export function isExcludedGlobTarget(cwd: string, resolvedTarget: string): boolean {
  const rel = relative(resolve(cwd), resolvedTarget);
  if (!rel) return false;
  if (rel.startsWith("..")) return true;
  const parts = rel.split(/[/\\]/).map((part) => part.toLowerCase());
  return parts.some((part) => EXCLUDED_GLOB_DIR_SEGMENTS.has(part));
}

export function isRepoRootTarget(cwd: string, resolvedTarget: string): boolean {
  return relative(resolve(cwd), resolvedTarget) === "";
}

export type GlobPolicyDecision =
  | { allow: true }
  | { allow: false; reason: string };

export function evaluateGlobToolCall(input: {
  pattern: string;
  targetDirectory?: string;
  cwd: string;
}): GlobPolicyDecision {
  const cwd = resolve(input.cwd);
  const target = resolveGlobTarget(cwd, input.targetDirectory);
  if (isExcludedGlobTarget(cwd, target)) {
    return {
      allow: false,
      reason: `禁止对 .git / .svn / build 或仓库外目录做 glob（目标=${target}）。改用子目录或 VCS 命令。`,
    };
  }
  if (isUnboundedGlobPattern(input.pattern) && isRepoRootTarget(cwd, target)) {
    return {
      allow: false,
      reason:
        "禁止对仓库根做无界 glob（** / **/*）。请用 grep，或指定子目录 / 带文件名片段的 glob。不要与 grep 并行再扫整仓。",
    };
  }
  return { allow: true };
}

export function globArgsFromUnknown(value: unknown): {
  pattern: string;
  targetDirectory?: string;
} {
  const record =
    value !== null && typeof value === "object" && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  const nested =
    record.tool_input ??
    record.toolInput ??
    record.arguments ??
    record.args ??
    record.input;
  const source =
    nested !== null && typeof nested === "object" && !Array.isArray(nested)
      ? (nested as Record<string, unknown>)
      : record;
  const pattern = firstString(
    source,
    "glob_pattern",
    "globPattern",
    "pattern",
  );
  const targetDirectory = firstString(
    source,
    "target_directory",
    "targetDirectory",
    "path",
  );
  return {
    pattern,
    ...(targetDirectory ? { targetDirectory } : {}),
  };
}

export function isGlobToolName(name: string): boolean {
  const normalized = name.trim().toLowerCase();
  return normalized === "glob" || normalized === "glob_file_search";
}

export function toolNameFromHookInput(value: unknown): string {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return "";
  }
  const record = value as Record<string, unknown>;
  return firstString(record, "tool_name", "toolName", "name", "tool");
}

export function cwdFromHookInput(value: unknown, fallback = process.cwd()): string {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return fallback;
  }
  const record = value as Record<string, unknown>;
  return firstString(record, "cwd", "workspace_roots") || fallback;
}

function firstString(
  record: Record<string, unknown>,
  ...keys: string[]
): string {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) return value.trim();
    if (Array.isArray(value) && typeof value[0] === "string" && value[0].trim()) {
      return value[0].trim();
    }
  }
  return "";
}
