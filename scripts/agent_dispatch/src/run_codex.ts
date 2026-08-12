import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  effortToCodexConfigArgs,
  type DispatchJob,
  type DispatchResult,
} from "./types.js";

function resolveCodexBin(): string {
  return process.platform === "win32" ? "codex.cmd" : "codex";
}

export async function runCodex(job: DispatchJob): Promise<DispatchResult> {
  const temp = mkdtempSync(join(tmpdir(), "kanban-codex-"));
  const promptFile = join(temp, "prompt.txt");
  const lastMessageFile = join(temp, "last.txt");
  writeFileSync(promptFile, job.prompt, "utf8");

  const args = [
    "exec",
    "--full-auto",
    "--skip-git-repo-check",
    "--cd",
    job.cwd,
    "-o",
    lastMessageFile,
    ...effortToCodexConfigArgs(job.effort),
  ];
  if (job.model?.trim()) {
    args.push("-m", job.model.trim());
  }
  // 从文件读 prompt：用 stdin
  args.push("-");

  console.log(`Codex args=${args.join(" ")}`);

  try {
    const code = await new Promise<number>((resolvePromise, reject) => {
      const child = spawn(resolveCodexBin(), args, {
        cwd: job.cwd,
        env: process.env,
        stdio: ["pipe", "pipe", "pipe"],
        shell: process.platform === "win32",
      });
      child.stdout.on("data", (buf: Buffer) => {
        process.stdout.write(buf);
      });
      child.stderr.on("data", (buf: Buffer) => {
        process.stderr.write(buf);
      });
      child.on("error", reject);
      child.stdin.write(readFileSync(promptFile));
      child.stdin.end();
      child.on("close", (exitCode) => resolvePromise(exitCode ?? 1));
    });

    let summary: string | undefined;
    try {
      summary = readFileSync(lastMessageFile, "utf8").trim();
    } catch {
      summary = undefined;
    }

    if (code === 0) {
      return {
        ok: true,
        summary: summary || "Codex 实施完成",
      };
    }
    return {
      ok: false,
      error: `Codex 退出码 ${code}`,
      summary,
    };
  } finally {
    try {
      rmSync(temp, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
}
