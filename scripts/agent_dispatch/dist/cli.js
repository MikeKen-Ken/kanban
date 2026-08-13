// src/cli.ts
import { readFileSync as readFileSync2, writeFileSync as writeFileSync2 } from "node:fs";
import { resolve } from "node:path";
import { Cursor } from "@cursor/sdk";

// src/run_codex.ts
import { spawn } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// src/types.ts
function resolveModelParams(job) {
  if (job.modelParams && job.modelParams.length > 0) {
    return job.modelParams;
  }
  switch (job.effort) {
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
function effortToCodexConfigArgs(job) {
  const params = resolveModelParams(job) ?? [];
  const effort = params.find(
    (p) => p.id === "reasoning_effort" || p.id === "model_reasoning_effort"
  );
  if (effort) {
    return ["-c", `model_reasoning_effort=${effort.value}`];
  }
  if (params.some((p) => p.id === "fast" && p.value === "true")) {
    return ["-c", "model_reasoning_effort=low"];
  }
  return [];
}

// src/run_codex.ts
function resolveCodexCommand() {
  const packageRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
  const bundledCli = join(
    packageRoot,
    "node_modules",
    "@openai",
    "codex",
    "bin",
    "codex.js"
  );
  if (existsSync(bundledCli)) {
    return {
      command: process.execPath,
      prefixArgs: [bundledCli],
      shell: false
    };
  }
  return {
    command: "codex",
    prefixArgs: [],
    shell: process.platform === "win32"
  };
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
    ...effortToCodexConfigArgs(job)
  ];
  if (job.model?.trim()) {
    args.push("-m", job.model.trim());
  }
  args.push("-");
  console.log(`Codex args=${args.join(" ")}`);
  try {
    const code = await new Promise((resolvePromise, reject) => {
      const codex = resolveCodexCommand();
      const child = spawn(codex.command, [...codex.prefixArgs, ...args], {
        cwd: job.cwd,
        env: process.env,
        stdio: ["pipe", "pipe", "pipe"],
        shell: codex.shell
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
      return { ok: true, summary: summary || "Codex \u4F1A\u8BDD\u5B8C\u6210" };
    }
    return { ok: false, error: `Codex \u9000\u51FA\u7801 ${code}`, summary };
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
  const params = resolveModelParams(job);
  console.log(
    `Cursor \u6A21\u578B=${modelId} params=${JSON.stringify(params ?? [])}`
  );
  try {
    const result = await Agent.prompt(job.prompt, {
      apiKey,
      model: {
        id: modelId,
        ...params ? { params } : {}
      },
      local: {
        cwd: job.cwd,
        // 需要用户级 MCP（kanbanMCP）与项目规则
        settingSources: ["user", "project"]
      }
    });
    if (result.status === "error") {
      return {
        ok: false,
        error: `Cursor run \u5931\u8D25\uFF1A${result.id ?? "unknown"}`,
        summary: typeof result.result === "string" ? result.result : void 0
      };
    }
    const summary = typeof result.result === "string" ? result.result : result.status === "finished" ? "Cursor \u4F1A\u8BDD\u5B8C\u6210" : `Cursor \u72B6\u6001\uFF1A${result.status}`;
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
function sleep(ms) {
  return new Promise((resolve2) => setTimeout(resolve2, ms));
}
function isRetryableError(err) {
  if (err && typeof err === "object") {
    if ("isRetryable" in err && err.isRetryable) {
      return true;
    }
    const message = err instanceof Error ? err.message : String(err);
    const lower = message.toLowerCase();
    if (lower.includes("network") || lower.includes("fetch failed") || lower.includes("connect timeout") || lower.includes("econnreset") || lower.includes("etimedout") || lower.includes("und_err_connect_timeout")) {
      return true;
    }
    if ("cause" in err && err.cause) {
      return isRetryableError(err.cause);
    }
  }
  return false;
}
function formatListModelsError(err) {
  if (err && typeof err === "object" && "message" in err) {
    const message = String(err.message).trim();
    if (message) return `Cursor.models.list \u5931\u8D25\uFF1A${message}`;
  }
  return `Cursor.models.list \u5931\u8D25\uFF1A${String(err)}`;
}
async function withRetry(operation, fn, options) {
  const maxAttempts = options?.maxAttempts ?? 3;
  const baseDelayMs = options?.baseDelayMs ?? 1e3;
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      if (attempt >= maxAttempts || !isRetryableError(err)) {
        throw err;
      }
      const delayMs = baseDelayMs * 2 ** (attempt - 1);
      console.error(
        `${operation} \u5931\u8D25\uFF08\u7B2C ${attempt}/${maxAttempts} \u6B21\uFF09\uFF0C${delayMs}ms \u540E\u91CD\u8BD5\u2026`
      );
      await sleep(delayMs);
    }
  }
  throw lastError;
}
function writeResult(outPath, result) {
  writeFileSync2(outPath, JSON.stringify(result, null, 2), "utf8");
}
function normalizeModelParameterValues(input) {
  if (!Array.isArray(input)) return [];
  return input.map((item) => {
    if (item && typeof item === "object" && "value" in item) {
      const value = item.value;
      const displayName = item.displayName;
      return value == null ? null : {
        value: String(value),
        ...displayName == null ? {} : { displayName: String(displayName) }
      };
    }
    return item == null ? null : { value: String(item) };
  }).filter(
    (item) => item !== null && item.value.length > 0
  );
}
async function listModels() {
  const apiKey = process.env.CURSOR_API_KEY?.trim();
  if (!apiKey) {
    console.error("\u7F3A\u5C11 CURSOR_API_KEY");
    process.exitCode = 2;
    return;
  }
  let models;
  try {
    models = await withRetry("\u62C9\u53D6\u6A21\u578B\u5217\u8868", () => Cursor.models.list({ apiKey }));
  } catch (err) {
    console.error(formatListModelsError(err));
    process.exitCode = 2;
    return;
  }
  const payload = {
    models: models.map((m) => ({
      id: m.id,
      displayName: m.displayName,
      description: m.description,
      parameters: (m.parameters ?? []).map((p) => ({
        id: p.id,
        displayName: p.displayName,
        values: normalizeModelParameterValues(
          p.values ?? p.enum
        )
      })),
      variants: (m.variants ?? []).map((variant) => ({
        displayName: variant.displayName,
        description: variant.description,
        isDefault: variant.isDefault,
        params: variant.params
      }))
    }))
  };
  process.stdout.write(`${JSON.stringify(payload)}
`);
}
async function runJob(jobPath) {
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
    result = job.engine === "codex" ? await runCodex(job) : await runCursor(job);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    result = { ok: false, error: message };
  }
  writeResult(job.outPath, result);
  process.exitCode = result.ok ? 0 : 2;
}
async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes("--list-models")) {
    await listModels();
    return;
  }
  const idx = argv.indexOf("--job");
  if (idx < 0 || !argv[idx + 1]) {
    throw new Error("\u7528\u6CD5: node cli.js --job <job.json> | --list-models");
  }
  await runJob(resolve(argv[idx + 1]));
}
main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
