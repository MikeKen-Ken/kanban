import { isAbsolute, relative, resolve } from "node:path";

/** Worker injection: locate with targeted grep / narrow glob; do not enumerate the repo root unboundedly. */
export const DISPATCH_SEARCH_POLICY = `## Search scope (Worker)

When locating code, MUST use grep or a glob limited by filename/directory, and MUST specify a subdirectory.
MUST NOT unbounded-glob the repository root (\`**\`, \`**/*\`, \`**/*.*\`).
MUST NOT run an unbounded glob in parallel with grep; when grep already returned candidate files, read those paths directly.
MUST NOT point a glob target at \`.git\`, \`.svn\`, or \`build\`.
Locate UI or feature entry points from the currently selected repository's directory layout, project rules, and concrete clues on the card; do not assume a framework, source root, or any product-specific path. When the card does not give a path, first inspect the repository's top-level directories and project notes in a limited way, then search inside candidate subdirectories. Before searching multiple directories, MUST confirm each directory exists; do not pass a non-existent candidate path to \`rg\`. When looking up a literal that contains quotes, parentheses, or other punctuation, prefer \`rg --fixed-strings -- <text> <confirmed-path>\`; write a regex only when pattern matching is actually required.
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
      reason: `Do not glob .git / .svn / build or paths outside the repository (target=${target}). Use a subdirectory or a VCS command instead.`,
    };
  }
  if (isUnboundedGlobPattern(input.pattern) && isRepoRootTarget(cwd, target)) {
    return {
      allow: false,
      reason:
        "Do not unbounded-glob the repository root (** / **/*). Use grep, or a glob that names a subdirectory / filename fragment. Do not scan the whole repo in parallel with grep.",
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
