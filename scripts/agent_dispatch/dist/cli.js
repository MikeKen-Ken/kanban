// src/cli.ts
import { readFileSync as readFileSync2, writeFileSync as writeFileSync2 } from "node:fs";
import { resolve } from "node:path";

// src/run_codex.ts
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// src/types.ts
function effortToCursorParams(effort) {
  switch (effort) {
    case "fast":
      return [{ id: "fast", value: "true" }];
    case "low":
      return [{ id: "reasoning_effort", value: "low" }];
    case "medium":
      return [{ id: "reasoning_effort", value: "medium" }];
    case "high":
      return [{ id: "reasoning_effort", value: "high" }];
    default:
      return void 0;
  }
}
function effortToCodexConfigArgs(effort) {
  switch (effort) {
    case "low":
      return ["-c", "model_reasoning_effort=low"];
    case "medium":
      return ["-c", "model_reasoning_effort=medium"];
    case "high":
      return ["-c", "model_reasoning_effort=high"];
    case "fast":
      return ["-c", "model_reasoning_effort=low"];
    default:
      return [];
  }
}

// src/run_codex.ts
function resolveCodexBin() {
  return process.platform === "win32" ? "codex.cmd" : "codex";
}
async function runCodex(job) {
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
    ...effortToCodexConfigArgs(job.effort)
  ];
  if (job.model?.trim()) {
    args.push("-m", job.model.trim());
  }
  args.push("-");
  console.log(`Codex args=${args.join(" ")}`);
  try {
    const code = await new Promise((resolvePromise, reject) => {
      const child = spawn(resolveCodexBin(), args, {
        cwd: job.cwd,
        env: process.env,
        stdio: ["pipe", "pipe", "pipe"],
        shell: process.platform === "win32"
      });
      child.stdout.on("data", (buf) => {
        process.stdout.write(buf);
      });
      child.stderr.on("data", (buf) => {
        process.stderr.write(buf);
      });
      child.on("error", reject);
      child.stdin.write(readFileSync(promptFile));
      child.stdin.end();
      child.on("close", (exitCode) => resolvePromise(exitCode ?? 1));
    });
    let summary;
    try {
      summary = readFileSync(lastMessageFile, "utf8").trim();
    } catch {
      summary = void 0;
    }
    if (code === 0) {
      return {
        ok: true,
        summary: summary || "Codex \u5B9E\u65BD\u5B8C\u6210"
      };
    }
    return {
      ok: false,
      error: `Codex \u9000\u51FA\u7801 ${code}`,
      summary
    };
  } finally {
    try {
      rmSync(temp, { recursive: true, force: true });
    } catch {
    }
  }
}

// src/run_cursor.ts
import { Agent, CursorAgentError } from "@cursor/sdk";
async function runCursor(job) {
  const apiKey = process.env.CURSOR_API_KEY?.trim();
  if (!apiKey) {
    return {
      ok: false,
      error: "\u7F3A\u5C11\u73AF\u5883\u53D8\u91CF CURSOR_API_KEY\uFF08Dashboard \u2192 Integrations / API Keys\uFF09"
    };
  }
  const modelId = job.model?.trim() || "composer-2.5";
  const params = effortToCursorParams(job.effort);
  console.log(`Cursor \u6A21\u578B=${modelId} effort=${job.effort ?? "default"}`);
  try {
    const result = await Agent.prompt(job.prompt, {
      apiKey,
      model: {
        id: modelId,
        ...params ? { params } : {}
      },
      local: {
        cwd: job.cwd,
        settingSources: ["project"]
      }
    });
    if (result.status === "error") {
      return {
        ok: false,
        error: `Cursor run \u5931\u8D25\uFF1A${result.id ?? "unknown"}`,
        summary: typeof result.result === "string" ? result.result : void 0
      };
    }
    const summary = typeof result.result === "string" ? result.result : result.status === "finished" ? "Cursor \u5B9E\u65BD\u5B8C\u6210" : `Cursor \u72B6\u6001\uFF1A${result.status}`;
    return { ok: result.status === "finished", summary };
  } catch (err) {
    if (err instanceof CursorAgentError) {
      return {
        ok: false,
        error: `Cursor \u542F\u52A8\u5931\u8D25\uFF1A${err.message}\uFF08retryable=${err.isRetryable}\uFF09`
      };
    }
    throw err;
  }
}

// src/cli.ts
function parseArgs(argv) {
  const idx = argv.indexOf("--job");
  if (idx < 0 || !argv[idx + 1]) {
    throw new Error("\u7528\u6CD5: node cli.js --job <job.json>");
  }
  return { jobPath: resolve(argv[idx + 1]) };
}
function writeResult(outPath, result) {
  writeFileSync2(outPath, JSON.stringify(result, null, 2), "utf8");
}
async function main() {
  const { jobPath } = parseArgs(process.argv.slice(2));
  const job = JSON.parse(readFileSync2(jobPath, "utf8"));
  if (!job.outPath) {
    throw new Error("job.outPath \u5FC5\u586B");
  }
  if (!job.cwd?.trim()) {
    writeResult(job.outPath, { ok: false, error: "cwd \u4E0D\u80FD\u4E3A\u7A7A" });
    process.exitCode = 2;
    return;
  }
  if (!job.prompt?.trim()) {
    writeResult(job.outPath, { ok: false, error: "prompt \u4E0D\u80FD\u4E3A\u7A7A" });
    process.exitCode = 2;
    return;
  }
  console.log(`engine=${job.engine} cwd=${job.cwd}`);
  let result;
  try {
    if (job.engine === "codex") {
      result = await runCodex(job);
    } else {
      result = await runCursor(job);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    result = { ok: false, error: message };
  }
  writeResult(job.outPath, result);
  process.exitCode = result.ok ? 0 : 2;
}
main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
