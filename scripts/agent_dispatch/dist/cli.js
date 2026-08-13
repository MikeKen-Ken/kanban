// src/cli.ts
import { readFileSync as readFileSync2, writeFileSync as writeFileSync2 } from "node:fs";
import { resolve } from "node:path";
import { Cursor as Cursor2 } from "@cursor/sdk";

// src/cursor_usage.ts
import { Cursor } from "@cursor/sdk";
function readPercent(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.min(100, value));
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed) ? Math.max(0, Math.min(100, parsed)) : void 0;
  }
  return void 0;
}
function pickPercent(record, keys) {
  for (const key of keys) {
    const value = readPercent(record[key]);
    if (value != null) return value;
  }
  return void 0;
}
function asRecord(value) {
  return value && typeof value === "object" ? value : null;
}
function parseUsageRecord(record) {
  const nested = asRecord(record.usage) ?? asRecord(record.planUsage) ?? asRecord(record.membershipType) ?? record;
  return {
    autoRemainingPercent: pickPercent(nested, [
      "autoRemainingPercent",
      "autoPercentRemaining",
      "autoRemaining",
      "composerRemainingPercent"
    ]),
    apiRemainingPercent: pickPercent(nested, [
      "apiRemainingPercent",
      "apiPercentRemaining",
      "apiRemaining"
    ])
  };
}
async function tryFetchUsagePools(apiKey) {
  const endpoints = [
    "https://api.cursor.com/auth/usage",
    "https://api.cursor.com/dashboard/get-monthly-invoice"
  ];
  for (const url of endpoints) {
    try {
      const response = await fetch(url, {
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json"
        }
      });
      if (!response.ok) continue;
      const json = await response.json();
      const record = asRecord(json);
      if (record == null) continue;
      const parsed = parseUsageRecord(record);
      if (parsed.autoRemainingPercent != null || parsed.apiRemainingPercent != null) {
        return parsed;
      }
    } catch {
    }
  }
  return {};
}
async function printCursorUsage() {
  const apiKey = process.env.CURSOR_API_KEY?.trim();
  if (!apiKey) {
    console.error("\u7F3A\u5C11 CURSOR_API_KEY");
    process.exitCode = 2;
    return;
  }
  let me;
  try {
    me = await Cursor.me({ apiKey });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const payload2 = {
      ok: false,
      error: `\u8BFB\u53D6 Cursor \u8D26\u53F7\u5931\u8D25\uFF1A${message}`
    };
    process.stdout.write(`${JSON.stringify(payload2)}
`);
    process.exitCode = 2;
    return;
  }
  const pools = await tryFetchUsagePools(apiKey);
  const payload = {
    ok: true,
    userEmail: me.userEmail,
    apiKeyName: me.apiKeyName,
    ...pools,
    message: pools.autoRemainingPercent == null && pools.apiRemainingPercent == null ? "\u4E2A\u4EBA\u5957\u9910\u7684 Auto+Composer / API \u53CC\u6C60\u5269\u4F59\u767E\u5206\u6BD4\u6CA1\u6709\u516C\u5F00 API\uFF0C\u8BF7\u6253\u5F00 Cursor Dashboard \u67E5\u770B\u3002" : void 0
  };
  process.stdout.write(`${JSON.stringify(payload)}
`);
}

// src/mcp_client.ts
import {
  Client,
  StreamableHTTPClientTransport
} from "@modelcontextprotocol/client";

// src/async_limit.ts
function settleWithin(ms, work) {
  return new Promise((resolve2) => {
    const timer = setTimeout(resolve2, ms);
    timer.unref?.();
    work.then(
      () => {
        clearTimeout(timer);
        resolve2();
      },
      () => {
        clearTimeout(timer);
        resolve2();
      }
    );
  });
}

// src/mcp_client.ts
var KanbanMcpClient = class {
  client = new Client({
    name: "kanban-agent-worker",
    version: "1.0.0"
  });
  async connect(endpoint) {
    await this.client.connect(
      new StreamableHTTPClientTransport(new URL(endpoint))
    );
  }
  async callJson(name, args) {
    const result = await this.client.callTool({ name, arguments: args });
    if (result.isError) {
      throw new Error(`${name} \u5931\u8D25\uFF1A${this.resultText(result)}`);
    }
    const text = this.resultText(result);
    try {
      return JSON.parse(text);
    } catch {
      throw new Error(`${name} \u8FD4\u56DE\u4E86\u65E0\u6548 JSON\uFF1A${text}`);
    }
  }
  async close() {
    await settleWithin(2e3, this.client.close());
  }
  resultText(result) {
    return result.content.filter(
      (item) => item.type === "text"
    ).map((item) => item.text).join("\n").trim();
  }
};

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
  const startedAt = Date.now();
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
    console.log(`Codex exec exitCode=${code} elapsedMs=${Date.now() - startedAt}`);
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
import { mkdirSync, writeSync } from "node:fs";
import { homedir } from "node:os";
import { join as join2 } from "node:path";
import { Agent, CursorAgentError, JsonlLocalAgentStore } from "@cursor/sdk";
function logLine(line) {
  writeSync(1, `${line}
`);
}
function clip(text, max = 240) {
  const compact = text.replace(/\s+/g, " ").trim();
  if (compact.length <= max) return compact;
  return `${compact.slice(0, max)}\u2026`;
}
function describeStep(step) {
  const type = String(step.type ?? "unknown");
  const message = step.message && typeof step.message === "object" ? step.message : void 0;
  switch (type) {
    case "assistantMessage":
      return `\u52A9\u624B\uFF1A${clip(String(message?.text ?? ""))}`;
    case "thinkingMessage":
      return "\u601D\u8003\u4E2D\u2026";
    case "toolCall":
      return `\u5DE5\u5177\uFF1A${String(message?.type ?? "tool")}`;
    case "shellConversationTurn":
    case "shell":
      return `\u547D\u4EE4\uFF1A${clip(String(message?.command ?? message?.text ?? ""))}`;
    default:
      return `\u6B65\u9AA4\uFF1A${type}`;
  }
}
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
  logLine(`Cursor \u6A21\u578B=${modelId} params=${JSON.stringify(params ?? [])}`);
  try {
    const startedAt = Date.now();
    let stepCount = 0;
    let toolCallCount = 0;
    const storeDir = join2(homedir(), ".cursor", "kanban-agent-jsonl-store");
    mkdirSync(storeDir, { recursive: true });
    logLine(
      `\u672C\u5730\u8FD0\u884C\uFF1AJSONL \u5B58\u50A8=${storeDir}\uFF1B\u6C99\u7BB1\u5173\u95ED\uFF1B\u7F51\u7EDC\u4F20\u8F93\u4F7F\u7528 SDK \u9ED8\u8BA4\u914D\u7F6E\uFF1B\u4EC5\u6CE8\u5165\u770B\u677F MCP\uFF08${job.mcpEndpoint}\uFF09\uFF0C\u4E0D\u52A0\u8F7D\u7528\u6237\u7EA7 MCP`
    );
    const agent = await Agent.create({
      apiKey,
      model: {
        id: modelId,
        ...params ? { params } : {}
      },
      mcpServers: {
        kanbanMCP: {
          type: "http",
          url: job.mcpEndpoint
        }
      },
      local: {
        cwd: job.cwd,
        settingSources: ["project"],
        store: new JsonlLocalAgentStore(storeDir),
        sandboxOptions: { enabled: false }
      }
    });
    try {
      logLine("\u672C\u5730\u4F1A\u8BDD\u5DF2\u521B\u5EFA\uFF0C\u5F00\u59CB\u6267\u884C\u2026");
      const run = await agent.send(job.prompt, {
        onStep: ({ step }) => {
          try {
            stepCount += 1;
            if (step.type === "toolCall") toolCallCount += 1;
            logLine(describeStep(step));
          } catch {
            logLine("\u6536\u5230\u4E00\u6B65\u8FDB\u5EA6");
          }
        }
      });
      const result = await run.wait();
      logLine(
        `Cursor run id=${result.id} status=${result.status} steps=${stepCount} tools=${toolCallCount} elapsedMs=${Date.now() - startedAt}`
      );
      if (result.usage) {
        logLine(
          `\u672C\u4F1A\u8BDD token\uFF1Ainput=${result.usage.inputTokens} output=${result.usage.outputTokens} total=${result.usage.totalTokens}`
        );
      }
      if (result.status === "error") {
        return {
          ok: false,
          error: `Cursor run \u5931\u8D25\uFF1A${result.error?.message ?? result.id}`,
          summary: typeof result.result === "string" ? result.result : void 0
        };
      }
      const summary = typeof result.result === "string" ? result.result : result.status === "finished" ? "Cursor \u4F1A\u8BDD\u5B8C\u6210" : `Cursor \u72B6\u6001\uFF1A${result.status}`;
      return { ok: result.status === "finished", summary };
    } finally {
      await settleWithin(8e3, agent[Symbol.asyncDispose]());
    }
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

// src/worker_log.ts
import { writeSync as writeSync2 } from "node:fs";
function workerLog(line) {
  writeSync2(1, `${line}
`);
}

// src/run_batch.ts
function cardState(card) {
  const columnId = String(card.columnId ?? "");
  const columnName = String(card.columnName ?? "");
  if (columnId === "verify" || columnName === "\u5F85\u9A8C\u8BC1") return "verify";
  if (columnId === "blocked" || columnName === "\u963B\u585E\u4E2D") return "blocked";
  return "active";
}
async function runBatch(job) {
  const mcp = new KanbanMcpClient();
  const limit = Math.max(1, Math.min(999, Math.trunc(job.cardLimit)));
  let processedCards = 0;
  workerLog(`Worker \u6279\u6B21\u542F\u52A8\uFF1Aendpoint=${job.mcpEndpoint} limit=${limit}`);
  try {
    await mcp.connect(job.mcpEndpoint);
    workerLog("Worker \u5DF2\u8FDE\u63A5\u770B\u677F MCP\uFF1BWorker \u53EA\u8BFB\u68C0\u67E5\u961F\u5217\uFF0CSkill \u81EA\u5DF1\u9886\u53D6\u5361\u7247");
    for (let index = 1; index <= limit; index += 1) {
      workerLog(`\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 Worker \u5355\u5361\u8F6E\u6B21 ${index}/${limit} \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500`);
      const peek = await mcp.callJson("peek_next_card", {
        ...job.projectId ? { projectId: job.projectId } : {}
      });
      if (peek.found !== true) {
        workerLog(`[success] Worker \u68C0\u67E5\u7ED3\u679C\uFF1A\u65E0\u66F4\u591A\u5361\u7247\uFF1B\u5DF2\u5904\u7406 ${processedCards} \u5F20`);
        return {
          ok: true,
          summary: `Worker \u6279\u6B21\u5B8C\u6210\uFF1A\u5DF2\u5904\u7406 ${processedCards} \u5F20\uFF0C\u5F53\u524D\u65E0\u66F4\u591A\u5361\u7247`,
          processedCards
        };
      }
      await mcp.callJson("dispatch_begin_agent_session", {
        workerToken: job.workerToken
      });
      workerLog("Worker \u68C0\u67E5\u7ED3\u679C\uFF1A\u8FD8\u6709\u5361\u7247\uFF1B\u6B63\u5728\u521B\u5EFA\u5168\u65B0\u7684 Skill \u4F1A\u8BDD");
      const result = job.engine === "codex" ? await runCodex(job) : await runCursor(job);
      if (!result.ok) {
        return {
          ok: false,
          error: result.error ?? `\u7B2C ${index} \u6B21 Skill \u4F1A\u8BDD\u5931\u8D25`,
          processedCards
        };
      }
      workerLog("Worker \u5DF2\u786E\u8BA4 Agent \u4F1A\u8BDD\u7ED3\u675F\uFF0C\u6B63\u5728\u8BFB\u53D6\u672C\u8F6E\u5361\u7247\u72B6\u6001");
      const session = await mcp.callJson("dispatch_agent_session_status", {
        workerToken: job.workerToken
      });
      const cardId = String(session.cardId ?? "").trim();
      const projectId = String(session.projectId ?? job.projectId ?? "").trim();
      const deniedPickCount = Number(session.deniedPickCount ?? 0);
      if (deniedPickCount > 0) {
        return {
          ok: false,
          error: `\u7B2C ${index} \u6B21 Skill \u4F1A\u8BDD\u91CD\u590D\u8C03\u7528\u4E86 pick_next_card\uFF0CWorker \u505C\u6B62\u6279\u6B21`,
          processedCards
        };
      }
      if (session.pickClaimed !== true || !cardId) {
        return {
          ok: false,
          error: `\u7B2C ${index} \u6B21 Skill \u4F1A\u8BDD\u6CA1\u6709\u6210\u529F\u9886\u53D6\u4E00\u5F20\u5361\u7247\uFF0CWorker \u505C\u6B62\u6279\u6B21`,
          processedCards
        };
      }
      const latest = await mcp.callJson("get_card", {
        cardId,
        ...projectId ? { projectId } : {}
      });
      const state = cardState(latest);
      workerLog(
        `Worker \u72B6\u6001\u68C0\u67E5\uFF1AcardId=${cardId} column=${String(latest.columnName ?? latest.columnId ?? "\u672A\u77E5")}`
      );
      if (state === "blocked") {
        return {
          ok: false,
          error: `\u5361\u7247 ${cardId} \u5DF2\u8FDB\u5165\u963B\u585E\u4E2D\uFF0CWorker \u505C\u6B62\u6279\u6B21`,
          processedCards
        };
      }
      if (state !== "verify") {
        return {
          ok: false,
          error: `\u5361\u7247 ${cardId} \u672A\u8FDB\u5165\u5F85\u9A8C\u8BC1\uFF0CWorker \u5224\u5B9A\u672C\u8F6E\u672A\u5B8C\u6210\u5E76\u505C\u6B62\u6279\u6B21`,
          processedCards
        };
      }
      processedCards += 1;
      workerLog(`[success] Worker \u786E\u8BA4\u7B2C ${index} \u6B21 Skill \u53EA\u5904\u7406\u4E00\u5F20\u4E14\u5DF2\u9001\u9A8C\uFF1B\u4F1A\u8BDD\u5DF2\u91CA\u653E`);
    }
    workerLog(`[success] Worker \u6279\u6B21\u5B8C\u6210\uFF1A\u5DF2\u8FBE\u5230\u4E0A\u9650\u5E76\u5904\u7406 ${processedCards} \u5F20`);
    return {
      ok: true,
      summary: `Worker \u6279\u6B21\u5B8C\u6210\uFF1A\u5DF2\u8FBE\u5230\u4E0A\u9650\u5E76\u5904\u7406 ${processedCards} \u5F20`,
      processedCards
    };
  } finally {
    workerLog("Worker \u6B63\u5728\u5173\u95ED\u770B\u677F MCP \u8FDE\u63A5\u2026");
    await mcp.close().catch(() => void 0);
    workerLog("Worker \u5DF2\u5173\u95ED\u770B\u677F MCP \u8FDE\u63A5");
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
    models = await withRetry("\u62C9\u53D6\u6A21\u578B\u5217\u8868", () => Cursor2.models.list({ apiKey }));
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
  if (!job.mcpEndpoint?.trim()) {
    writeResult(job.outPath, { ok: false, error: "mcpEndpoint \u4E0D\u80FD\u4E3A\u7A7A" });
    process.exitCode = 2;
    return;
  }
  if (!job.workerToken?.trim()) {
    writeResult(job.outPath, { ok: false, error: "workerToken \u4E0D\u80FD\u4E3A\u7A7A" });
    process.exitCode = 2;
    return;
  }
  if (!Number.isFinite(job.cardLimit) || job.cardLimit < 1) {
    writeResult(job.outPath, { ok: false, error: "cardLimit \u5FC5\u987B\u5927\u4E8E 0" });
    process.exitCode = 2;
    return;
  }
  console.log(`engine=${job.engine} cwd=${job.cwd}`);
  let result;
  try {
    result = await runBatch(job);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    result = { ok: false, error: message };
  }
  writeResult(job.outPath, result);
  const code = result.ok ? 0 : 2;
  process.exitCode = code;
  process.exit(code);
}
async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes("--list-models")) {
    await listModels();
    return;
  }
  if (argv.includes("--usage")) {
    await printCursorUsage();
    return;
  }
  const idx = argv.indexOf("--job");
  if (idx < 0 || !argv[idx + 1]) {
    throw new Error(
      "\u7528\u6CD5: node cli.js --job <job.json> | --list-models | --usage"
    );
  }
  await runJob(resolve(argv[idx + 1]));
}
main().catch((err) => {
  console.error(err);
  process.exit(1);
});
