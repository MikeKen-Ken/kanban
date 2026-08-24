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
    lower.includes("not a git repo") ||
    lower.includes("\u4E0D\u662F git \u4ED3\u5E93")
  );
}

/** \u4E0E Skill \u539F\u5148\u7684 `git status --short` \u4E00\u81F4：\u810F\u5219\u4E0D\u8981\u5F00\u4F1A\u8BDD。 */
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
