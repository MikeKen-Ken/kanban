import { spawnSync } from "node:child_process";

export type GitWorkingTree =
  | { kind: "not_git" }
  | { kind: "clean" }
  | { kind: "dirty"; output: string }
  | { kind: "unknown"; output: string };

function combinedOutput(status: {
  stdout?: string | null;
  stderr?: string | null;
}): string {
  const stdout = String(status.stdout ?? "").trim();
  const stderr = String(status.stderr ?? "").trim();
  if (!stdout) return stderr;
  if (!stderr) return stdout;
  return `${stdout}\n${stderr}`;
}

function looksLikeNotGit(text: string): boolean {
  const lower = text.toLowerCase();
  return (
    lower.includes("not a git repository") ||
    lower.includes("not a git repo")
  );
}

/** 与 Skill 原先的 `git status --short` 一致：脏则不要开会话。 */
export function inspectGitWorkingTree(cwd: string): GitWorkingTree {
  const root = cwd.trim();
  if (!root) return { kind: "not_git" };
  const status = spawnSync("git", ["-C", root, "status", "--short"], {
    encoding: "utf8",
    windowsHide: true,
  });
  const output = combinedOutput(status);
  if (status.error) {
    const message = status.error.message || String(status.error);
    if (looksLikeNotGit(message)) return { kind: "not_git" };
    return { kind: "unknown", output: message };
  }
  if (status.status !== 0) {
    if (looksLikeNotGit(output) || status.status === 128) {
      return { kind: "not_git" };
    }
    return { kind: "unknown", output };
  }
  if (!output) return { kind: "clean" };
  return { kind: "dirty", output };
}
