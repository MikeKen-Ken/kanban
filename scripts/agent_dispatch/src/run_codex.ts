import { spawn } from "node:child_process";
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
import {
  effortToCodexConfigArgs,
  type DispatchJob,
  type DispatchResult,
} from "./types.js";

function resolveCodexCommand(): {
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
    ...effortToCodexConfigArgs(job),
  ];
  if (job.model?.trim()) {
    args.push("-m", job.model.trim());
  }
  args.push("-");

  console.log(`Codex args=${args.join(" ")}`);

  try {
    const code = await new Promise<number>((resolvePromise, reject) => {
      const codex = resolveCodexCommand();
      const child = spawn(codex.command, [...codex.prefixArgs, ...args], {
        cwd: job.cwd,
        env: process.env,
        stdio: ["pipe", "pipe", "pipe"],
        shell: codex.shell,
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
      return { ok: true, summary: summary || "Codex 会话完成" };
    }
    return { ok: false, error: `Codex 退出码 ${code}`, summary };
  } finally {
    try {
      rmSync(temp, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
}
