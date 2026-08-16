// src/cli.ts
import { readFileSync as readFileSync3, writeFileSync as writeFileSync4 } from "node:fs";
import { resolve as resolve2 } from "node:path";
import { Cursor as Cursor2 } from "@cursor/sdk";

// src/cancellation.ts
import { existsSync } from "node:fs";
var WorkerCancelledError = class extends Error {
  constructor(message = "\u5DF2\u53D6\u6D88") {
    super(message);
    this.name = "WorkerCancelledError";
  }
};
var WorkerCancellation = class {
  cancelled = false;
  drainAfterCurrent = false;
  skipRequested = false;
  reason = "\u5DF2\u53D6\u6D88";
  callbacks = /* @__PURE__ */ new Set();
  cancelFileTimer;
  drainFileTimer;
  skipFileTimer;
  signalInstalled = false;
  watchCancelFile(path) {
    const check = () => {
      if (this.cancelled) return;
      try {
        if (existsSync(path)) this.cancel("\u5DF2\u53D6\u6D88");
      } catch {
      }
    };
    check();
    this.cancelFileTimer = setInterval(check, 200);
    this.cancelFileTimer.unref?.();
  }
  watchDrainFile(path) {
    const check = () => {
      if (this.drainAfterCurrent || this.cancelled) return;
      try {
        if (existsSync(path)) this.requestDrainAfterCurrent();
      } catch {
      }
    };
    check();
    this.drainFileTimer = setInterval(check, 200);
    this.drainFileTimer.unref?.();
  }
  watchSkipFile(path) {
    const check = () => {
      if (this.skipRequested || this.cancelled) return;
      try {
        if (existsSync(path)) this.requestSkipCurrentSession();
      } catch {
      }
    };
    check();
    this.skipFileTimer = setInterval(check, 200);
    this.skipFileTimer.unref?.();
  }
  installSignalHandlers() {
    if (this.signalInstalled) return;
    this.signalInstalled = true;
    const onSignal = () => {
      this.cancel("\u5DF2\u53D6\u6D88");
    };
    process.once("SIGTERM", onSignal);
    process.once("SIGINT", onSignal);
  }
  get isCancelled() {
    return this.cancelled;
  }
  get isSkipRequested() {
    return this.skipRequested;
  }
  get shouldStopAfterCurrentSession() {
    return this.cancelled || this.drainAfterCurrent;
  }
  requestDrainAfterCurrent() {
    if (this.cancelled || this.drainAfterCurrent) return;
    this.drainAfterCurrent = true;
  }
  /** 跳过当前 Skill 会话并继续批次下一张；不标记整批取消。 */
  requestSkipCurrentSession() {
    if (this.cancelled || this.skipRequested) return;
    this.skipRequested = true;
    for (const callback of this.callbacks) {
      void this.invoke(callback);
    }
  }
  clearSkipRequest() {
    this.skipRequested = false;
  }
  onCancel(callback) {
    this.callbacks.add(callback);
    if (this.cancelled) void this.invoke(callback);
  }
  cancel(reason = "\u5DF2\u53D6\u6D88") {
    if (this.cancelled) return;
    this.cancelled = true;
    this.reason = reason;
    for (const callback of this.callbacks) {
      void this.invoke(callback);
    }
  }
  throwIfCancelled() {
    if (this.cancelled) throw new WorkerCancelledError(this.reason);
  }
  dispose() {
    if (this.cancelFileTimer) {
      clearInterval(this.cancelFileTimer);
      this.cancelFileTimer = void 0;
    }
    if (this.drainFileTimer) {
      clearInterval(this.drainFileTimer);
      this.drainFileTimer = void 0;
    }
    if (this.skipFileTimer) {
      clearInterval(this.skipFileTimer);
      this.skipFileTimer = void 0;
    }
  }
  async invoke(callback) {
    try {
      await callback();
    } catch {
    }
  }
};

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
    ...pools
  };
  process.stdout.write(`${JSON.stringify(payload)}
`);
}

// src/codex_models.ts
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
async function listCodexModels(codex) {
  const child = spawn(
    codex.command,
    [...codex.prefixArgs, "app-server", "--stdio"],
    { stdio: ["pipe", "pipe", "pipe"], shell: codex.shell }
  );
  const stderr = [];
  child.stderr.on("data", (chunk) => stderr.push(chunk.toString("utf8")));
  try {
    const client = new AppServerClient(child);
    await client.request("initialize", {
      clientInfo: { name: "kanban-agent-dispatch", version: "1.0.0" },
      capabilities: { experimentalApi: false }
    });
    client.notify("initialized", {});
    const models = [];
    let cursor;
    do {
      const result = await client.request("model/list", {
        cursor: cursor ?? null,
        includeHidden: false
      });
      models.push(...result.data ?? []);
      cursor = result.nextCursor;
    } while (cursor);
    return models.map(toCatalogItem).filter((model) => model.id.length > 0);
  } catch (error) {
    const detail = stderr.join("").trim();
    throw new Error(detail ? `${String(error)}
${detail}` : String(error));
  } finally {
    child.kill();
  }
}
function toCatalogItem(model) {
  const id = (model.model ?? model.id ?? "").trim();
  const efforts = (model.supportedReasoningEfforts ?? []).map((option) => ({
    value: option.reasoningEffort?.trim() ?? "",
    displayName: effortLabel(option.reasoningEffort ?? "")
  })).filter((option) => option.value.length > 0);
  const defaultEffort = model.defaultReasoningEffort?.trim();
  return {
    id,
    displayName: model.displayName,
    description: model.description,
    parameters: efforts.length === 0 ? [] : [{
      id: "model_reasoning_effort",
      displayName: "\u63A8\u7406\u7A0B\u5EA6",
      values: efforts
    }],
    variants: defaultEffort ? [{
      displayName: `\u9ED8\u8BA4\uFF08${effortLabel(defaultEffort)}\uFF09`,
      isDefault: true,
      params: [{ id: "model_reasoning_effort", value: defaultEffort }]
    }] : []
  };
}
function effortLabel(value) {
  const labels = {
    minimal: "Minimal",
    none: "None",
    low: "Low",
    medium: "Medium",
    high: "High",
    xhigh: "XHigh",
    max: "Max"
  };
  return labels[value] ?? value;
}
var AppServerClient = class {
  constructor(child) {
    this.child = child;
    const lines = createInterface({ input: child.stdout });
    lines.on("line", (line) => this.handleLine(line));
    child.on("error", (error) => this.rejectAll(error));
    child.on("close", (code) => {
      if (this.pending.size > 0) {
        this.rejectAll(new Error(`Codex app-server \u5DF2\u9000\u51FA\uFF08${code ?? 1}\uFF09`));
      }
    });
  }
  nextId = 1;
  pending = /* @__PURE__ */ new Map();
  request(method, params) {
    const id = this.nextId++;
    const promise = new Promise((resolve3, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} \u8BF7\u6C42\u8D85\u65F6`));
      }, 15e3);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timeout);
          resolve3(value);
        },
        reject: (error) => {
          clearTimeout(timeout);
          reject(error);
        }
      });
    });
    this.write({ id, method, params });
    return promise;
  }
  notify(method, params) {
    this.write({ method, params });
  }
  write(message) {
    this.child.stdin.write(`${JSON.stringify(message)}
`);
  }
  handleLine(line) {
    let response;
    try {
      response = JSON.parse(line);
    } catch {
      return;
    }
    if (typeof response.id !== "number") return;
    const pending = this.pending.get(response.id);
    if (!pending) return;
    this.pending.delete(response.id);
    if (response.error) {
      pending.reject(new Error(response.error.message ?? "Codex app-server \u8BF7\u6C42\u5931\u8D25"));
    } else {
      pending.resolve(response.result);
    }
  }
  rejectAll(error) {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
};

// src/run_codex.ts
import { spawn as spawn2 } from "node:child_process";
import {
  existsSync as existsSync3,
  mkdtempSync as mkdtempSync2,
  readFileSync,
  rmSync,
  writeFileSync as writeFileSync2
} from "node:fs";
import { tmpdir as tmpdir2 } from "node:os";
import { dirname, join as join2 } from "node:path";
import { fileURLToPath } from "node:url";

// src/codex_mcp.ts
import {
  copyFileSync,
  existsSync as existsSync2,
  mkdirSync,
  mkdtempSync,
  writeFileSync
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
var AUTH_FILES = ["auth.json"];
function buildCodexAgentConfigToml(mcpUrl) {
  const url = mcpUrl.trim();
  return `[features]
rmcp_client = true

[mcp_servers.kanbanMCP]
url = "${url}"
`;
}
function resolveUserCodexHome(env = process.env) {
  const override = env.CODEX_HOME?.trim();
  if (override) return override;
  return join(homedir(), ".codex");
}
function createCodexAgentHome(options) {
  const prefix = join(
    options.tempRoot ?? tmpdir(),
    "kanban-codex-home-"
  );
  const home = mkdtempSync(prefix);
  mkdirSync(home, { recursive: true });
  writeFileSync(
    join(home, "config.toml"),
    buildCodexAgentConfigToml(options.mcpUrl),
    "utf8"
  );
  for (const name of AUTH_FILES) {
    const from = join(options.userCodexHome, name);
    if (existsSync2(from)) {
      copyFileSync(from, join(home, name));
    }
  }
  return { home };
}

// src/types.ts
function isReasoningParamId(id) {
  return id === "reasoning" || id === "reasoning_effort" || id === "model_reasoning_effort" || id === "effort" || id === "thinking";
}
function conservativeParamValue(id, values) {
  const allowed = values.map((value) => value.trim()).filter(Boolean);
  const middle = allowed[Math.floor((allowed.length - 1) / 2)];
  if (isReasoningParamId(id)) {
    if (allowed.includes("medium")) return "medium";
    return allowed.length === 0 ? "medium" : middle;
  }
  if (id === "fast") {
    if (allowed.includes("false")) return "false";
    return allowed.length === 0 ? "false" : middle;
  }
  return allowed.length === 0 ? void 0 : middle;
}
function parseEngine(raw, fallback) {
  const text = String(raw ?? "").trim();
  return text === "cursor" || text === "codex" ? text : fallback;
}
function parseCardParams(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
  return Object.entries(raw).filter(([, value]) => typeof value === "string" && value.trim() !== "").map(([id, value]) => ({ id, value: String(value).trim() }));
}
function engineFallback(job, engine) {
  const stored = job.engineDefaults?.[engine];
  if (stored) return stored;
  if (engine === job.engine) {
    return { model: job.model, modelParams: job.modelParams };
  }
  return {};
}
function mergeJobWithCardOverrides(job, claim) {
  const engine = parseEngine(claim.agentEngine, job.engine);
  const defaults = engineFallback(job, engine);
  const cardModel = String(claim.agentModelId ?? "").trim();
  const model = cardModel || defaults.model || void 0;
  const cardParams = parseCardParams(claim.agentModelParamValues);
  const byId = new Map(
    (defaults.modelParams ?? []).map((item) => [item.id, item])
  );
  for (const item of cardParams) byId.set(item.id, item);
  const catalog = defaults.models?.find((item) => item.id === model);
  const parameters = catalog?.parameters ?? [];
  if (parameters.length > 0) {
    const allowed = new Set(
      parameters.map((item) => String(item.id ?? "").trim()).filter(Boolean)
    );
    for (const id of [...byId.keys()]) {
      if (!allowed.has(id)) byId.delete(id);
    }
    for (const parameter of parameters) {
      const id = String(parameter.id ?? "").trim();
      if (!id || byId.has(id)) continue;
      const value = conservativeParamValue(id, parameter.values ?? []);
      if (value) byId.set(id, { id, value });
    }
  } else if (cardModel) {
    const hasReasoning = [...byId.keys()].some(isReasoningParamId);
    if (!hasReasoning) {
      byId.set("reasoning_effort", { id: "reasoning_effort", value: "medium" });
    }
  }
  const modelParams = [...byId.values()].map((item) => ({
    ...item,
    value: clampUnattendedParam(item, job.allowHighReasoning === true)
  }));
  return { ...job, engine, model, modelParams };
}
function clampUnattendedParam(param, allowHighReasoning) {
  const id = param.id.toLowerCase();
  const value = param.value.toLowerCase();
  if (isContextParamId(id)) {
    const tokens = parseTokenBudget(value);
    if (tokens != null && tokens > MAX_UNATTENDED_CONTEXT_TOKENS) {
      return "64k";
    }
  }
  if (allowHighReasoning) return param.value;
  const expensive = /* @__PURE__ */ new Set([
    "high",
    "xhigh",
    "extra_high",
    "very_high",
    "max",
    "maximum",
    "large",
    "xlarge",
    "huge"
  ]);
  if (expensive.has(value) && (isReasoningParamId(id) || isContextParamId(id) || id.includes("thinking"))) {
    return "medium";
  }
  return param.value;
}
function isContextParamId(id) {
  return id.toLowerCase().includes("context");
}
var MAX_UNATTENDED_CONTEXT_TOKENS = 64e3;
function parseTokenBudget(value) {
  const match = /^(\d+(?:\.\d+)?)\s*(k|m|kb|mb)?$/i.exec(value.trim());
  if (!match) return void 0;
  const amount = Number(match[1]);
  if (!Number.isFinite(amount)) return void 0;
  const unit = (match[2] ?? "").toLowerCase();
  if (unit === "m" || unit === "mb") return amount * 1e6;
  if (unit === "k" || unit === "kb") return amount * 1e3;
  return amount;
}
function resolveModelParams(job) {
  if (job.modelParams && job.modelParams.length > 0) {
    return job.modelParams.map((item) => ({
      ...item,
      value: clampUnattendedParam(item, job.allowHighReasoning === true)
    }));
  }
  switch (job.effort) {
    case "fast":
      return [{ id: "fast", value: "true" }];
    case "low":
      return [{ id: "reasoning_effort", value: "low" }];
    case "medium":
      return [{ id: "reasoning_effort", value: "medium" }];
    case "high":
      return [{
        id: "reasoning_effort",
        value: job.allowHighReasoning === true ? "high" : "medium"
      }];
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
  const packageRoot = join2(dirname(fileURLToPath(import.meta.url)), "..");
  const bundledCli = join2(
    packageRoot,
    "node_modules",
    "@openai",
    "codex",
    "bin",
    "codex.js"
  );
  if (existsSync3(bundledCli)) {
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
function buildCodexExecArgs(options) {
  const args = [
    "exec",
    "--approve-for-me",
    "--skip-git-repo-check",
    "--cd",
    options.cwd,
    "-o",
    options.lastMessageFile,
    ...options.extraConfigArgs ?? []
  ];
  if (options.model?.trim()) {
    args.push("-m", options.model.trim());
  }
  args.push("-");
  return args;
}
async function runCodex(job, cancellation) {
  const startedAt = Date.now();
  const mcpUrl = job.round.agentEndpointUrl.trim();
  if (!mcpUrl) {
    return { ok: false, error: "\u672C\u8F6E claim \u7F3A\u5C11 scoped MCP \u7AEF\u70B9" };
  }
  const temp = mkdtempSync2(join2(tmpdir2(), "kanban-codex-"));
  const promptFile = join2(temp, "prompt.txt");
  const lastMessageFile = join2(temp, "last.txt");
  try {
    writeFileSync2(promptFile, job.prompt, "utf8");
    const agentHome = createCodexAgentHome({
      mcpUrl,
      userCodexHome: resolveUserCodexHome(),
      tempRoot: temp
    });
    console.log(
      `Codex \u4F7F\u7528\u9694\u79BB CODEX_HOME\uFF0C\u4EC5\u6CE8\u5165\u7CBE\u7B80\u770B\u677F MCP\uFF08${mcpUrl}\uFF09`
    );
    const args = buildCodexExecArgs({
      cwd: job.cwd,
      lastMessageFile,
      extraConfigArgs: effortToCodexConfigArgs(job),
      model: job.model
    });
    console.log(`Codex args=${args.join(" ")}`);
    const code = await new Promise((resolvePromise, reject) => {
      const codex = resolveCodexCommand();
      let child;
      const killChild = () => {
        if (!child || child.killed) return;
        try {
          if (process.platform === "win32") {
            spawn2("taskkill", ["/PID", String(child.pid), "/T", "/F"], {
              shell: true
            });
          } else {
            child.kill("SIGTERM");
          }
        } catch {
        }
      };
      cancellation?.onCancel(killChild);
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        resolvePromise(130);
        return;
      }
      child = spawn2(codex.command, [...codex.prefixArgs, ...args], {
        cwd: job.cwd,
        env: { ...process.env, CODEX_HOME: agentHome.home },
        stdio: ["pipe", "pipe", "pipe"],
        shell: codex.shell
      });
      child.stdout?.on("data", (buf) => {
        process.stdout.write(buf);
      });
      child.stderr?.on("data", (buf) => {
        process.stderr.write(buf);
      });
      child.on("error", reject);
      if (!child.stdin) {
        reject(new Error("Codex stdin \u4E0D\u53EF\u7528"));
        return;
      }
      child.stdin.write(readFileSync(promptFile));
      child.stdin.end();
      child.on("close", (exitCode) => {
        if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
          resolvePromise(130);
          return;
        }
        resolvePromise(exitCode ?? 1);
      });
    });
    if (cancellation?.isSkipRequested) {
      console.log(`Codex exec skipped elapsedMs=${Date.now() - startedAt}`);
      return { ok: false, error: "\u5DF2\u8DF3\u8FC7" };
    }
    if (cancellation?.isCancelled) {
      console.log(`Codex exec cancelled elapsedMs=${Date.now() - startedAt}`);
      return { ok: false, error: "\u5DF2\u53D6\u6D88" };
    }
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

// src/git_working_tree.ts
import { spawnSync } from "node:child_process";
function combinedOutput(status) {
  const stdout = String(status.stdout ?? "").trim();
  const stderr = String(status.stderr ?? "").trim();
  if (!stdout) return stderr;
  if (!stderr) return stdout;
  return `${stdout}
${stderr}`;
}
function looksLikeNotGit(text) {
  const lower = text.toLowerCase();
  return lower.includes("not a git repository") || lower.includes("not a git repo") || lower.includes("\u4E0D\u662F git \u4ED3\u5E93");
}
function inspectGitWorkingTree(cwd) {
  const root = cwd.trim();
  if (!root) return { kind: "not_git" };
  const status = spawnSync("git", ["-C", root, "status", "--short"], {
    encoding: "utf8",
    windowsHide: true
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

// src/mcp_client.ts
import {
  Client,
  StreamableHTTPClientTransport
} from "@modelcontextprotocol/client";

// src/async_limit.ts
function settleWithin(ms, work) {
  return new Promise((resolve3) => {
    const timer = setTimeout(resolve3, ms);
    timer.unref?.();
    work.then(
      () => {
        clearTimeout(timer);
        resolve3();
      },
      () => {
        clearTimeout(timer);
        resolve3();
      }
    );
  });
}

// src/mcp_client.ts
var DEFAULT_MCP_TIMEOUT_MS = 3e4;
var MCP_CLAIM_TIMEOUT_MS = 12e4;
var MCP_FINALIZE_TIMEOUT_MS = 10 * 6e4;
function mcpTimeoutForTool(name) {
  switch (name) {
    case "dispatch_claim_next_card":
      return MCP_CLAIM_TIMEOUT_MS;
    case "dispatch_finalize":
      return MCP_FINALIZE_TIMEOUT_MS;
    default:
      return DEFAULT_MCP_TIMEOUT_MS;
  }
}
var KanbanMcpClient = class {
  client = new Client({
    name: "kanban-agent-worker",
    version: "1.0.0"
  });
  connected = false;
  timeoutMs;
  constructor(timeoutMs = DEFAULT_MCP_TIMEOUT_MS) {
    this.timeoutMs = timeoutMs;
  }
  async connect(endpoint) {
    await withTimeout(
      "\u8FDE\u63A5 MCP",
      this.timeoutMs,
      this.client.connect(
        new StreamableHTTPClientTransport(new URL(endpoint))
      )
    );
    this.connected = true;
  }
  async listTools() {
    const result = await withTimeout(
      "\u5217\u51FA MCP \u5DE5\u5177",
      this.timeoutMs,
      this.client.listTools()
    );
    return result.tools.map((tool) => tool.name).sort();
  }
  async callRaw(name, args, options) {
    const result = await withTimeout(
      `\u8C03\u7528 ${name}`,
      options?.timeoutMs ?? mcpTimeoutForTool(name),
      this.client.callTool({ name, arguments: args })
    );
    if (result.isError) {
      throw new Error(`${name} \u5931\u8D25\uFF1A${resultText(result)}`);
    }
    return result;
  }
  async callJson(name, args, options) {
    const result = await this.callRaw(name, args, options);
    const text = resultText(result);
    try {
      return JSON.parse(text);
    } catch {
      throw new Error(`${name} \u8FD4\u56DE\u4E86\u65E0\u6548 JSON\uFF1A${text}`);
    }
  }
  async close() {
    if (!this.connected) return;
    this.connected = false;
    await settleWithin(2e3, this.client.close());
  }
};
function parseClaimResult(result) {
  const text = resultText(result);
  let payload;
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("JSON \u9876\u5C42\u4E0D\u662F\u5BF9\u8C61");
    }
    payload = parsed;
  } catch (error) {
    throw new Error(
      `dispatch_claim_next_card \u8FD4\u56DE\u4E86\u65E0\u6548 JSON\uFF1A${error instanceof Error ? error.message : String(error)}`
    );
  }
  const images = result.content.filter(
    (item) => item.type === "image"
  ).map((item) => ({ data: item.data, mimeType: item.mimeType }));
  return { payload, images, raw: result };
}
function resultText(result) {
  return result.content.filter(
    (item) => item.type === "text"
  ).map((item) => item.text).join("\n").trim();
}
async function withTimeout(operation, timeoutMs, work) {
  let timer;
  try {
    return await Promise.race([
      work,
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(new Error(`${operation} \u8D85\u65F6\uFF08${timeoutMs}ms\uFF09`)),
          timeoutMs
        );
        timer.unref?.();
      })
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

// src/run_cursor.ts
import { mkdirSync as mkdirSync2 } from "node:fs";
import { homedir as homedir2 } from "node:os";
import { join as join3 } from "node:path";
import { Agent, CursorAgentError, JsonlLocalAgentStore } from "@cursor/sdk";

// src/cursor_token_usage.ts
function asCount(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.trunc(value));
}
function toDashboardTokenUsage(raw) {
  const input = asCount(raw.inputTokens);
  const output = asCount(raw.outputTokens);
  const cacheRead = asCount(raw.cacheReadTokens);
  const cacheWrite = asCount(raw.cacheWriteTokens);
  const reportedTotal = asCount(raw.totalTokens);
  const cache = cacheRead + cacheWrite;
  const extra = reportedTotal - input - output;
  const inferredCache = cache > 0 ? cache : Math.max(0, extra);
  const inferredRead = cacheRead > 0 ? cacheRead : inferredCache;
  const inferredWrite = cacheWrite;
  const cacheSum = inferredRead + inferredWrite;
  const inputLooksInclusive = cacheSum > 0 && input >= cacheSum && extra >= cacheSum;
  if (inputLooksInclusive) {
    const uncached = input - cacheSum;
    return {
      inputTokens: uncached,
      outputTokens: output,
      cacheReadTokens: inferredRead,
      cacheWriteTokens: inferredWrite,
      totalTokens: uncached + output + cacheSum
    };
  }
  return {
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: inferredRead,
    cacheWriteTokens: inferredWrite,
    totalTokens: input + output + cacheSum
  };
}
function formatSessionTokenLog(raw) {
  const usage = toDashboardTokenUsage(raw);
  return `\u672C\u4F1A\u8BDD token\uFF1Ainput=${usage.inputTokens} output=${usage.outputTokens} cacheRead=${usage.cacheReadTokens} cacheWrite=${usage.cacheWriteTokens} total=${usage.totalTokens}`;
}

// src/worker_log.ts
import { writeSync } from "node:fs";
function workerLog(line, source = "worker") {
  writeSync(1, `[${source}] ${line}
`);
}

// src/run_cursor.ts
function logLine(line, source = "worker") {
  workerLog(line, source);
}
function logLines(lines, source = "worker") {
  for (const line of lines) {
    logLine(line, source);
  }
}
function formatJson(value, max = 4e3) {
  if (value === void 0) return "";
  try {
    const text = JSON.stringify(value);
    if (text.length <= max) return text;
    return `${text.slice(0, max)}\u2026`;
  } catch {
    return String(value);
  }
}
function expandMultiline(prefix, body) {
  const trimmed = body.trimEnd();
  if (!trimmed) return [`${prefix}\uFF08\u7A7A\uFF09`];
  const lines = trimmed.split(/\r?\n/);
  const result = [`${prefix}${lines[0]}`];
  for (let i = 1; i < lines.length; i++) {
    result.push(`  \u2502 ${lines[i]}`);
  }
  return result;
}
function asRecord2(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}
function pickString(message, ...keys) {
  if (!message) return "";
  for (const key of keys) {
    const value = message[key];
    if (typeof value === "string" && value.trim()) return value;
  }
  return "";
}
function parseJsonRecord(value) {
  if (typeof value !== "string") return void 0;
  const trimmed = value.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return void 0;
  try {
    return asRecord2(JSON.parse(trimmed));
  } catch {
    return void 0;
  }
}
function usefulJson(value, max = 4e3) {
  if (value === void 0 || value === null) return "";
  if (typeof value === "string") return value.trim();
  const text = formatJson(value, max);
  if (!text || text === "{}" || text === "[]" || text === "null") return "";
  return text;
}
function toolPayload(step) {
  return asRecord2(step.message) ?? asRecord2(step.toolCall) ?? asRecord2(step.call) ?? asRecord2(step.tool) ?? asRecord2(asRecord2(step.message)?.toolCall) ?? asRecord2(asRecord2(step.message)?.call);
}
function extractToolDetail(payload) {
  if (!payload) return "";
  const nested = asRecord2(payload.args) ?? asRecord2(payload.arguments) ?? asRecord2(payload.input) ?? asRecord2(payload.params) ?? asRecord2(asRecord2(payload.function)?.arguments) ?? parseJsonRecord(payload.args) ?? parseJsonRecord(payload.arguments) ?? parseJsonRecord(asRecord2(payload.function)?.arguments);
  const command = pickString(
    payload,
    "command",
    "cmd",
    "shellCommand",
    "query",
    "pattern",
    "glob_pattern",
    "globPattern"
  );
  if (command) return command;
  if (nested) {
    const nestedCommand = pickString(
      nested,
      "command",
      "cmd",
      "shellCommand",
      "query",
      "pattern",
      "glob_pattern",
      "globPattern"
    );
    if (nestedCommand) {
      const extra = { ...nested };
      delete extra.command;
      delete extra.cmd;
      delete extra.shellCommand;
      const rest = usefulJson(extra, 2e3);
      return rest ? `${nestedCommand}  ${rest}` : nestedCommand;
    }
    return usefulJson(nested);
  }
  const rawArgs = payload.args ?? payload.arguments ?? payload.input ?? payload.params;
  if (typeof rawArgs === "string" && rawArgs.trim()) return rawArgs.trim();
  return "";
}
function isShellTool(name) {
  return /^(shell|bash|cmd|powershell|pwsh)$/i.test(name);
}
function describeStep(step) {
  const record = asRecord2(step) ?? {};
  const type = String(record.type ?? "unknown");
  const message = toolPayload(record);
  switch (type) {
    case "assistantMessage":
      return {
        lines: expandMultiline("\u52A9\u624B\uFF1A", String(message?.text ?? "")),
        source: "ai"
      };
    case "thinkingMessage": {
      const text = pickString(message, "text", "thinking", "content");
      return {
        lines: text ? expandMultiline("\u601D\u8003\uFF1A", text) : [],
        source: "ai"
      };
    }
    case "toolCall": {
      const toolName = pickString(message, "name", "toolName", "functionName", "type") || pickString(record, "name", "toolName") || "tool";
      const detail = extractToolDetail(message);
      if (!detail) {
        return { lines: [], source: isShellTool(toolName) ? "shell" : "mcp" };
      }
      if (isShellTool(toolName)) {
        return { lines: expandMultiline("\u547D\u4EE4\uFF1A", detail), source: "shell" };
      }
      return {
        lines: expandMultiline(`\u5DE5\u5177\uFF1A${toolName} `, detail),
        source: "mcp"
      };
    }
    case "toolResult": {
      const toolName = pickString(message, "name", "toolName", "type") || "tool";
      const result = message?.result ?? message?.output ?? message?.content ?? message?.text;
      if (result === void 0) {
        return { lines: [], source: "mcp" };
      }
      const body = typeof result === "string" ? result : formatJson(result);
      if (!String(body).trim()) return { lines: [], source: "mcp" };
      return {
        lines: expandMultiline(`\u5DE5\u5177\u7ED3\u679C\uFF1A${toolName} `, body),
        source: "mcp"
      };
    }
    case "shellConversationTurn":
    case "shell": {
      const command = extractToolDetail(message) || pickString(message, "command", "text");
      if (!command) return { lines: [], source: "shell" };
      return {
        lines: expandMultiline("\u547D\u4EE4\uFF1A", command),
        source: "shell"
      };
    }
    default: {
      const detail = message ? usefulJson(message, 800) : "";
      if (!detail) return { lines: [], source: "worker" };
      return {
        lines: [`\u6B65\u9AA4\uFF1A${type} ${detail}`],
        source: "worker"
      };
    }
  }
}
async function runCursor(job, cancellation) {
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
  const agentMcpUrl = job.round.agentEndpointUrl.trim();
  if (!agentMcpUrl) {
    return { ok: false, error: "\u672C\u8F6E claim \u7F3A\u5C11 scoped MCP \u7AEF\u70B9" };
  }
  try {
    process.chdir(job.cwd);
    const startedAt = Date.now();
    let stepCount = 0;
    let toolCallCount = 0;
    const storeDir = join3(homedir2(), ".cursor", "kanban-agent-jsonl-store");
    mkdirSync2(storeDir, { recursive: true });
    logLine(
      `\u672C\u5730\u8FD0\u884C\uFF1AJSONL \u5B58\u50A8=${storeDir}\uFF1B\u6C99\u7BB1\u5173\u95ED\uFF1B\u4EC5\u6CE8\u5165\u770B\u677F\u7CBE\u7B80 MCP\uFF08${agentMcpUrl}\uFF09\uFF0C\u4E0D\u52A0\u8F7D\u7528\u6237\u7EA7 MCP\uFF1BsettingSources \u4E3A\u7A7A\uFF08\u4E0D\u6CE8\u5165\u9879\u76EE\u89C4\u5219\u4E0E\u4E2A\u4EBA Skill\uFF09`
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
          url: agentMcpUrl
        }
      },
      local: {
        cwd: job.cwd,
        // 流程已由注入的 Skill 正文给出。加载 project 会把仓库规则与个人 Skill
        // 整包塞进会话（日志里常见 skillCount=21、ruleCount=32），cacheRead 可达上百万。
        settingSources: [],
        store: new JsonlLocalAgentStore(storeDir),
        autoReview: true,
        sandboxOptions: { enabled: false }
      }
    });
    try {
      logLine("\u672C\u5730\u4F1A\u8BDD\u5DF2\u521B\u5EFA\uFF0C\u5F00\u59CB\u6267\u884C\u2026");
      const run = await agent.send({
        text: job.prompt,
        images: job.round.images
      }, {
        onStep: ({ step }) => {
          try {
            stepCount += 1;
            if (step.type === "toolCall") toolCallCount += 1;
            const described = describeStep(
              step
            );
            if (described.lines.length > 0) {
              logLines(described.lines, described.source);
            }
          } catch {
            logLine("\u6536\u5230\u4E00\u6B65\u8FDB\u5EA6");
          }
        }
      });
      cancellation?.onCancel(() => {
        void run.cancel().catch(() => void 0);
      });
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        await run.cancel().catch(() => void 0);
      }
      const result = await run.wait();
      if (cancellation?.isSkipRequested) {
        logLine("Cursor \u4F1A\u8BDD\u5DF2\u7531\u7528\u6237\u8DF3\u8FC7", "worker");
        return { ok: false, error: "\u5DF2\u8DF3\u8FC7" };
      }
      if (cancellation?.isCancelled || result.status === "cancelled") {
        logLine("Cursor \u4F1A\u8BDD\u5DF2\u7531\u7528\u6237\u505C\u6B62", "worker");
        return { ok: false, error: "\u5DF2\u53D6\u6D88" };
      }
      logLine(
        `Cursor run id=${result.id} status=${result.status} steps=${stepCount} tools=${toolCallCount} elapsedMs=${Date.now() - startedAt}`
      );
      if (result.usage) {
        logLine(formatSessionTokenLog(result.usage));
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

// src/session_context.ts
import {
  existsSync as existsSync4,
  mkdtempSync as mkdtempSync3,
  readFileSync as readFileSync2,
  rmSync as rmSync2,
  writeFileSync as writeFileSync3
} from "node:fs";
import { tmpdir as tmpdir3 } from "node:os";
import { isAbsolute, join as join4 } from "node:path";
function readBatchArchitecture(cwd) {
  const path = join4(cwd, "docs", "Architecture.md");
  if (!existsSync4(path)) return "\u4ED3\u5E93\u672A\u63D0\u4F9B docs/Architecture.md\u3002";
  return readFileSync2(path, "utf8");
}
function createSessionContext(options) {
  const tempDir = mkdtempSync3(
    join4(options.tempRoot ?? tmpdir3(), "kanban-agent-session-")
  );
  const attachmentPaths = [];
  const payload = structuredClone(options.claim.payload);
  const fileAttachments = Array.isArray(payload.fileAttachments) ? payload.fileAttachments : [];
  for (let index = 0; index < fileAttachments.length; index += 1) {
    const raw = fileAttachments[index];
    if (!isRecord(raw)) continue;
    const content = typeof raw.contentBase64 === "string" ? raw.contentBase64 : "";
    delete raw.contentBase64;
    if (!content || raw.included === false) continue;
    const fileName = safeFileName(
      typeof raw.fileName === "string" ? raw.fileName : `attachment-${index}.bin`,
      `attachment-${index}.bin`
    );
    const path = uniquePath(tempDir, `${index + 1}-${fileName}`);
    writeFileSync3(path, Buffer.from(content, "base64"));
    raw.absolutePath = path;
    attachmentPaths.push(path);
  }
  const imagePaths = [];
  for (let index = 0; index < options.claim.images.length; index += 1) {
    const image = options.claim.images[index];
    const path = join4(
      tempDir,
      `image-${index + 1}.${extensionForMime(image.mimeType)}`
    );
    writeFileSync3(path, Buffer.from(image.data, "base64"));
    imagePaths.push(path);
  }
  const prompt = [
    options.basePrompt.trim(),
    "",
    "# Worker \u6CE8\u5165\u7684\u672C\u8F6E\u4E0A\u4E0B\u6587",
    "",
    "\u672C\u8F6E\u5361\u7247\u5DF2\u9886\u53D6\u3002\u4EE5\u4E0B\u4E0A\u4E0B\u6587\u662F\u552F\u4E00\u4EFB\u52A1\u8303\u56F4\uFF1B\u4E0D\u8981\u518D\u6B21\u8BFB\u53D6 Skill \u6216\u9886\u53D6\u5176\u4ED6\u5361\u7247\u3002",
    "",
    "## \u5361\u7247\u4E0A\u4E0B\u6587\uFF08JSON\uFF09",
    "",
    "```json",
    JSON.stringify(payload, null, 2),
    "```",
    "",
    "## \u4E34\u65F6\u9644\u4EF6\u7EDD\u5BF9\u8DEF\u5F84",
    "",
    ...attachmentPaths.length === 0 ? ["- \u65E0\u6587\u4EF6\u9644\u4EF6"] : attachmentPaths.map((path) => `- \u6587\u4EF6\uFF1A${path}`),
    ...imagePaths.length === 0 ? ["- \u65E0\u56FE\u7247\u4E34\u65F6\u8DEF\u5F84"] : imagePaths.map((path) => `- \u56FE\u7247\uFF1A${path}`),
    "",
    "\u8FD9\u4E9B\u8DEF\u5F84\u4F4D\u4E8E\u7CFB\u7EDF\u4E34\u65F6\u4F1A\u8BDD\u76EE\u5F55\uFF0C\u53EA\u5728\u672C\u8F6E\u6709\u6548\uFF1B\u4E0D\u8981\u590D\u5236\u5230\u4ED3\u5E93\u3002",
    "",
    "## \u5DF2\u7F13\u5B58\u7684 docs/Architecture.md",
    "",
    options.architecture.trim(),
    "",
    "Worker \u5DF2\u5728\u6279\u6B21\u5F00\u59CB\u65F6\u8BFB\u53D6\u4EE5\u4E0A\u67B6\u6784\u6587\u6863\uFF0C\u672C\u8F6E\u4E0D\u8981\u91CD\u590D\u8BFB\u53D6\u3002"
  ].join("\n");
  return {
    prompt,
    images: options.claim.images,
    attachmentPaths: [...attachmentPaths, ...imagePaths],
    tempDir,
    cleanup: () => {
      rmSync2(tempDir, { recursive: true, force: true });
    }
  };
}
function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function safeFileName(value, fallback) {
  const normalized = value.replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_").replace(/[. ]+$/g, "").trim();
  return normalized || fallback;
}
function uniquePath(root, fileName) {
  const path = join4(root, fileName);
  if (!isAbsolute(path)) throw new Error("\u4E34\u65F6\u9644\u4EF6\u8DEF\u5F84\u4E0D\u662F\u7EDD\u5BF9\u8DEF\u5F84");
  return path;
}
function extensionForMime(mimeType) {
  switch (mimeType.toLowerCase()) {
    case "image/png":
      return "png";
    case "image/gif":
      return "gif";
    case "image/webp":
      return "webp";
    default:
      return "jpg";
  }
}

// src/verification_runner.ts
import { spawn as spawn4 } from "node:child_process";
import { isAbsolute as isAbsolute2, relative, resolve, sep } from "node:path";

// src/windows_spawn.ts
import { spawn as spawn3 } from "node:child_process";
import { existsSync as existsSync5, statSync } from "node:fs";
import { delimiter, extname, join as join5 } from "node:path";
var WINDOWS_BATCH_EXTS = /* @__PURE__ */ new Set([".bat", ".cmd"]);
function spawnUnexpanded(command, args, options) {
  if (process.platform !== "win32") {
    return spawn3(command, args, { ...options, shell: false });
  }
  const resolved = resolveWindowsExecutable(command, envFrom(options));
  if (resolved && isWindowsBatchFile(resolved)) {
    const invocation = buildWindowsCmdInvocation(resolved, args);
    return spawn3(invocation.command, invocation.args, {
      ...options,
      shell: false,
      windowsVerbatimArguments: true
    });
  }
  return spawn3(resolved ?? command, args, { ...options, shell: false });
}
function resolveWindowsExecutable(command, env = process.env) {
  const trimmed = command.trim();
  if (!trimmed) return void 0;
  if (hasPathSeparator(trimmed)) {
    return resolveWithPathext(trimmed, env);
  }
  const pathValue = env.Path ?? env.PATH ?? "";
  for (const dir of pathValue.split(delimiter)) {
    if (!dir.trim()) continue;
    const found = resolveWithPathext(join5(dir, trimmed), env);
    if (found) return found;
  }
  return void 0;
}
function buildWindowsCmdInvocation(executable, args) {
  const inner = [quoteCmdArg(executable), ...args.map(quoteCmdArg)].join(" ");
  return {
    command: process.env.ComSpec || "cmd.exe",
    args: ["/d", "/s", "/v:off", "/c", `"${inner}"`]
  };
}
function quoteCmdArg(value) {
  return `"${value.replace(/%/g, "%%").replace(/"/g, '""')}"`;
}
function isWindowsBatchFile(file) {
  return WINDOWS_BATCH_EXTS.has(extname(file).toLowerCase());
}
function hasPathSeparator(command) {
  return command.includes("/") || command.includes("\\") || /^[A-Za-z]:/.test(command);
}
function resolveWithPathext(base, env) {
  const ext = extname(base);
  if (ext) return isExistingFile(base) ? base : void 0;
  const pathext = env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD";
  for (const item of pathext.split(";")) {
    const suffix = item.trim();
    if (!suffix) continue;
    const candidate = base + suffix;
    if (isExistingFile(candidate)) return candidate;
  }
  return void 0;
}
function isExistingFile(path) {
  try {
    return existsSync5(path) && statSync(path).isFile();
  } catch {
    return false;
  }
}
function envFrom(options) {
  if (options.env && typeof options.env === "object") {
    return options.env;
  }
  return process.env;
}

// src/verification_runner.ts
var DEFAULT_VERIFICATION_TIMEOUT_MS = 10 * 6e4;
var MAX_VERIFICATION_TIMEOUT_MS = 15 * 6e4;
var MAX_OUTPUT_CHARS = 16e3;
async function runVerificationCommand(item, repoRoot) {
  const startedAt = Date.now();
  const timeoutMs = clampTimeout(item.timeoutMs);
  const expectedExitCode = Number.isInteger(item.expectedExitCode) ? item.expectedExitCode : 0;
  const commandCwd = item.cwd?.trim() || ".";
  const commandSummary = summarizeCommand(item.executable, item.args);
  let resolvedCwd;
  try {
    resolvedCwd = resolveCommandCwd(repoRoot, commandCwd);
  } catch (error) {
    return {
      commandSummary,
      executable: item.executable,
      args: [...item.args],
      cwd: commandCwd,
      exitCode: -1,
      durationMs: Date.now() - startedAt,
      output: error instanceof Error ? error.message : String(error),
      timedOut: false,
      passed: false
    };
  }
  return new Promise((resolvePromise) => {
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let settled = false;
    const spawnOptions = {
      cwd: resolvedCwd,
      shell: false,
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    };
    let child;
    try {
      child = spawnUnexpanded(item.executable, item.args, spawnOptions);
    } catch (error) {
      resolvePromise({
        commandSummary,
        executable: item.executable,
        args: [...item.args],
        cwd: commandCwd,
        exitCode: -1,
        durationMs: Date.now() - startedAt,
        output: error instanceof Error ? error.message : String(error),
        timedOut: false,
        passed: false
      });
      return;
    }
    child.stdout?.on("data", (chunk) => {
      stdout = appendTruncated(stdout, String(chunk));
    });
    child.stderr?.on("data", (chunk) => {
      stderr = appendTruncated(stderr, String(chunk));
    });
    const finish = (exitCode) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(killGrace);
      const output = combineOutput(stdout, stderr);
      resolvePromise({
        commandSummary,
        executable: item.executable,
        args: [...item.args],
        cwd: commandCwd,
        exitCode,
        durationMs: Date.now() - startedAt,
        output,
        timedOut,
        passed: !timedOut && exitCode === expectedExitCode
      });
    };
    child.on("error", (error) => {
      stderr = appendTruncated(stderr, error.message);
      finish(-1);
    });
    child.on("close", (code) => finish(timedOut ? 124 : code ?? -1));
    let killGrace;
    const timer = setTimeout(() => {
      timedOut = true;
      terminateProcessTree(child.pid);
      killGrace = setTimeout(() => finish(124), 3e3);
      killGrace.unref?.();
    }, timeoutMs);
    timer.unref?.();
  });
}
async function runVerificationCommands(commands, cwd) {
  const results = [];
  for (const command of commands) {
    const result = await runVerificationCommand(command, cwd);
    results.push(result);
    if (!result.passed) break;
  }
  return results;
}
function formatVerificationFailure(failed) {
  if (failed.timedOut) {
    return `\u9A8C\u8BC1\u547D\u4EE4\u8D85\u65F6\uFF1A${failed.commandSummary}`;
  }
  const detail = failed.output.split(/\r?\n/).map((line) => line.trim()).find((line) => line.length > 0);
  const base = `\u9A8C\u8BC1\u547D\u4EE4\u5931\u8D25\uFF08exitCode=${failed.exitCode}\uFF09\uFF1A${failed.commandSummary}`;
  return detail ? `${base}\uFF1B${detail}` : base;
}
function clampTimeout(value) {
  if (!Number.isFinite(value)) return DEFAULT_VERIFICATION_TIMEOUT_MS;
  return Math.max(100, Math.min(MAX_VERIFICATION_TIMEOUT_MS, Math.trunc(value)));
}
function appendTruncated(current, next) {
  const combined = current + next;
  if (combined.length <= MAX_OUTPUT_CHARS) return combined;
  return `\u2026\uFF08\u524D\u6587\u5DF2\u622A\u65AD\uFF09${combined.slice(-MAX_OUTPUT_CHARS)}`;
}
function combineOutput(stdout, stderr) {
  const out = stdout.trim();
  const err = stderr.trim();
  if (!out) return err;
  if (!err) return out;
  return `stdout:
${out}

stderr:
${err}`;
}
function terminateProcessTree(pid) {
  if (!pid) return;
  try {
    if (process.platform === "win32") {
      const killer = spawn4("taskkill", ["/PID", String(pid), "/T", "/F"], {
        windowsHide: true,
        stdio: "ignore"
      });
      killer.unref();
    } else {
      process.kill(pid, "SIGTERM");
    }
  } catch {
  }
}
function resolveCommandCwd(repoRoot, cwd) {
  const root = resolve(repoRoot);
  if (isAbsolute2(cwd)) {
    throw new Error(`\u9A8C\u8BC1 cwd \u5FC5\u987B\u662F\u4ED3\u5E93\u5185\u76F8\u5BF9\u8DEF\u5F84\uFF1A${cwd}`);
  }
  const target = resolve(root, cwd);
  const relation = relative(root, target);
  if (relation === ".." || relation.startsWith(`..${sep}`) || isAbsolute2(relation)) {
    throw new Error(`\u9A8C\u8BC1 cwd \u9003\u51FA\u4ED3\u5E93\uFF1A${cwd}`);
  }
  return target;
}
function summarizeCommand(executable, args) {
  return [executable, ...args].map((part) => /\s|"/.test(part) ? JSON.stringify(part) : part).join(" ");
}

// src/run_batch.ts
var SCOPED_TOOL_NAMES = [
  "block_card",
  "ready_to_submit",
  "submit_consultation"
];
var defaultDependencies = {
  connectMcp: async (endpoint) => {
    const client = new KanbanMcpClient();
    await client.connect(endpoint);
    return client;
  },
  inspectGit: inspectGitWorkingTree,
  readArchitecture: readBatchArchitecture,
  createContext: createSessionContext,
  runAgent: (roundJob, cancellation) => roundJob.engine === "codex" ? runCodex(roundJob, cancellation) : runCursor(roundJob, cancellation),
  runVerification: runVerificationCommands
};
async function runBatch(job, cancellation, dependencies = defaultDependencies) {
  const limit = Math.max(1, Math.min(999, Math.trunc(job.cardLimit)));
  const architecture = dependencies.readArchitecture(job.cwd);
  const mcp = await dependencies.connectMcp(job.mcpEndpoint);
  let processedCards = 0;
  workerLog(`Worker \u6279\u6B21\u542F\u52A8\uFF1Aendpoint=${job.mcpEndpoint} limit=${limit}`);
  const cancelledResult = () => ({
    ok: false,
    error: "\u5DF2\u53D6\u6D88",
    processedCards
  });
  const drainedResult = () => ({
    ok: true,
    summary: `\u5DF2\u5728\u5F53\u524D\u4F1A\u8BDD\u7ED3\u675F\u540E\u505C\u6B62\uFF1B\u5DF2\u5904\u7406 ${processedCards} \u5F20`,
    processedCards
  });
  try {
    workerLog("Worker \u5DF2\u8FDE\u63A5\u5B8C\u6574\u770B\u677F MCP\uFF0C\u6B63\u5728\u6062\u590D\u672A\u5B8C\u6210\u6536\u5C3E");
    const recovery = await recoverPendingSessions(
      mcp,
      job,
      dependencies
    );
    if (!recovery.ok) {
      return { ...recovery, processedCards };
    }
    processedCards += recovery.processedCards ?? 0;
    for (let index = 1; index <= limit; index += 1) {
      if (cancellation?.shouldStopAfterCurrentSession) {
        return cancellation.isCancelled ? cancelledResult() : drainedResult();
      }
      workerLog(`\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 Worker \u5355\u5361\u8F6E\u6B21 ${index}/${limit} \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500`);
      const peek = await mcp.callJson("peek_next_card", {
        ...job.projectId ? { projectId: job.projectId } : {}
      });
      if (peek.found !== true) {
        return completedResult(processedCards, "\u5F53\u524D\u65E0\u66F4\u591A\u5361\u7247");
      }
      const treeError = gitPreflightError(dependencies.inspectGit(job.cwd));
      if (treeError) {
        return { ok: false, error: treeError, processedCards };
      }
      const expectedCardId = String(peek.cardId ?? "").trim();
      const claim = parseClaimResult(
        await mcp.callRaw("dispatch_claim_next_card", {
          workerToken: job.workerToken,
          ...expectedCardId ? { expectedCardId } : {}
        })
      );
      if (claim.payload.found !== true) {
        return completedResult(processedCards, "claim \u65F6\u961F\u5217\u5DF2\u4E3A\u7A7A");
      }
      const cardId = requiredString(claim.payload, "cardId");
      const sessionId = requiredString(claim.payload, "sessionId");
      const agentEndpointUrl = requiredString(
        claim.payload,
        "agentEndpointUrl"
      );
      let scoped;
      let context;
      let terminalRecorded = false;
      try {
        scoped = await dependencies.connectMcp(agentEndpointUrl);
        const tools = await scoped.listTools();
        if (JSON.stringify(tools) !== JSON.stringify(SCOPED_TOOL_NAMES)) {
          throw new Error(
            `scoped MCP \u5DE5\u5177\u95E8\u7981\u5931\u8D25\uFF1A\u5B9E\u9645=${tools.join(",")}\uFF0C\u671F\u671B=${SCOPED_TOOL_NAMES.join(",")}`
          );
        }
        context = dependencies.createContext({
          basePrompt: job.prompt,
          architecture,
          claim
        });
        const overridden = mergeJobWithCardOverrides(job, claim.payload);
        const roundJob = {
          ...overridden,
          prompt: context.prompt,
          round: {
            cardId,
            sessionId,
            agentEndpointUrl,
            images: context.images,
            attachmentPaths: context.attachmentPaths
          }
        };
        logModelOverride(job, roundJob, cardId);
        const agentResult = await dependencies.runAgent(roundJob, cancellation);
        if (cancellation?.isSkipRequested || agentResult.error === "\u5DF2\u8DF3\u8FC7") {
          cancellation?.clearSkipRequest();
          await mcp.callJson("dispatch_skip_agent_session", {
            workerToken: job.workerToken,
            sessionId,
            reason: "\u7528\u6237\u8BF7\u6C42\u8DF3\u8FC7\u5F53\u524D\u5361\u7247"
          });
          terminalRecorded = true;
          const afterSkip = dependencies.inspectGit(job.cwd);
          if (afterSkip.kind === "dirty") {
            return {
              ok: false,
              error: `\u8DF3\u8FC7\u540E\u5DE5\u4F5C\u533A\u4E0D\u5E72\u51C0\uFF0C\u505C\u6B62\u6279\u6B21\uFF1A
${afterSkip.output}`,
              processedCards
            };
          }
          if (afterSkip.kind === "unknown") {
            return {
              ok: false,
              error: `\u8DF3\u8FC7\u540E\u65E0\u6CD5\u5224\u65AD\u5DE5\u4F5C\u533A\u72B6\u6001\uFF1A${afterSkip.output}`,
              processedCards
            };
          }
          continue;
        }
        if (cancellation?.isCancelled || agentResult.error === "\u5DF2\u53D6\u6D88") {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            "\u7528\u6237\u53D6\u6D88\u5F53\u524D Agent \u4F1A\u8BDD",
            true
          );
          terminalRecorded = true;
          return cancelledResult();
        }
        if (!agentResult.ok) {
          await mcp.callJson("dispatch_fail_agent_session", {
            workerToken: job.workerToken,
            sessionId,
            reason: agentResult.error ?? "Agent \u4F1A\u8BDD\u5931\u8D25"
          });
          terminalRecorded = true;
          return {
            ok: false,
            error: agentResult.error ?? `\u7B2C ${index} \u6B21 Agent \u4F1A\u8BDD\u5931\u8D25`,
            processedCards
          };
        }
        const status = await mcp.callJson("dispatch_agent_session_status", {
          workerToken: job.workerToken
        });
        assertSessionMatches(status, sessionId, cardId);
        const projectId = String(
          status.projectId ?? claim.payload.projectId ?? job.projectId ?? ""
        ).trim();
        const latest = await mcp.callJson("get_card", {
          cardId,
          ...projectId ? { projectId } : {}
        });
        const state = cardState(latest);
        const pending = asRecord3(status.pending);
        if (state === "blocked") {
          return {
            ok: false,
            error: `\u5361\u7247 ${cardId} \u5DF2\u8FDB\u5165\u963B\u585E\u4E2D\uFF0CWorker \u505C\u6B62\u6279\u6B21`,
            processedCards
          };
        }
        if (state === "verify" && pending == null) {
          processedCards += 1;
          workerLog(`[success] \u54A8\u8BE2\u5361 ${cardId} \u5DF2\u9001\u4EA4\u9A8C\u8BC1`);
          continue;
        }
        if (!pending || pending.status !== "declared") {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            `\u5B9E\u65BD\u5361 ${cardId} \u672A\u58F0\u660E ready_to_submit`
          );
          terminalRecorded = true;
          return {
            ok: false,
            error: `\u5B9E\u65BD\u5361 ${cardId} \u672A\u58F0\u660E ready_to_submit`,
            processedCards
          };
        }
        const finalized = await validateAndFinalize(
          mcp,
          job,
          pending,
          dependencies
        );
        if (!finalized.ok) {
          if (!finalized.preservePending && !terminalRecorded) {
            await recordRoundFailure(
              mcp,
              job,
              sessionId,
              finalized.error ?? "Worker \u6536\u5C3E\u5931\u8D25"
            );
            terminalRecorded = true;
          }
          return { ...finalized, processedCards };
        }
        terminalRecorded = true;
        processedCards += 1;
        workerLog(`[success] \u5361\u7247 ${cardId} \u5DF2\u9A8C\u8BC1\u3001\u63D0\u4EA4\u5E76\u9001\u4EA4\u4EBA\u5DE5\u9A8C\u8BC1`);
        if (cancellation?.shouldStopAfterCurrentSession) {
          return cancellation.isCancelled ? cancelledResult() : drainedResult();
        }
      } catch (error) {
        const reason = error instanceof WorkerCancelledError ? "\u7528\u6237\u53D6\u6D88\u5F53\u524D Agent \u4F1A\u8BDD" : `Agent \u4F1A\u8BDD\u5F02\u5E38\uFF1A${error instanceof Error ? error.message : String(error)}`;
        if (!terminalRecorded) {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            reason,
            error instanceof WorkerCancelledError
          );
        }
        const tree = dependencies.inspectGit(job.cwd);
        const dirtySuffix = tree.kind === "dirty" ? `
\u5DE5\u4F5C\u533A\u4E0D\u5E72\u51C0\uFF0C\u505C\u6B62\u6279\u6B21\uFF1A
${tree.output}` : tree.kind === "unknown" ? `
\u65E0\u6CD5\u5224\u65AD\u5DE5\u4F5C\u533A\u72B6\u6001\uFF0C\u505C\u6B62\u6279\u6B21\uFF1A${tree.output}` : "";
        return error instanceof WorkerCancelledError ? cancelledResult() : { ok: false, error: `${reason}${dirtySuffix}`, processedCards };
      } finally {
        context?.cleanup();
        await scoped?.close().catch(() => void 0);
        await mcp.callJson("dispatch_close_agent_session", {
          workerToken: job.workerToken
        }).catch(() => void 0);
      }
    }
    return completedResult(processedCards, "\u5DF2\u8FBE\u5230\u6279\u6B21\u4E0A\u9650");
  } catch (error) {
    if (error instanceof WorkerCancelledError) return cancelledResult();
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message, processedCards };
  } finally {
    await mcp.close().catch(() => void 0);
    workerLog("Worker \u5DF2\u5173\u95ED\u5B8C\u6574\u770B\u677F MCP \u8FDE\u63A5");
  }
}
async function recoverPendingSessions(mcp, job, dependencies) {
  const listed = await mcp.callJson("dispatch_list_pending", {
    workerToken: job.workerToken
  });
  const pending = Array.isArray(listed.pending) ? listed.pending : [];
  let processedCards = 0;
  for (const raw of pending) {
    const record = asRecord3(raw);
    if (!record) continue;
    const sessionId = requiredString(record, "sessionId");
    const recovered = await mcp.callJson("dispatch_recover", {
      workerToken: job.workerToken,
      sessionId
    });
    const result = await validateAndFinalize(
      mcp,
      job,
      recovered,
      dependencies
    );
    if (!result.ok) return { ...result, processedCards };
    processedCards += 1;
    workerLog(`[success] \u5DF2\u6062\u590D pending \u4F1A\u8BDD ${sessionId}`);
  }
  return { ok: true, processedCards };
}
async function validateAndFinalize(mcp, job, pending, dependencies) {
  const sessionId = requiredString(pending, "sessionId");
  const cardId = requiredString(pending, "cardId");
  let status = String(pending.status ?? "");
  if (status === "declared") {
    const manualReason = String(pending.manualVerificationReason ?? "").trim();
    const commands = parseVerificationCommands(pending.verificationCommands);
    const results = manualReason ? [] : await dependencies.runVerification(commands, job.cwd);
    const failed = results.find((item) => !item.passed);
    const recorded = await mcp.callJson("dispatch_record_validation_results", {
      workerToken: job.workerToken,
      sessionId,
      results: results.map(({
        commandSummary,
        executable,
        args,
        cwd,
        exitCode,
        durationMs,
        timedOut,
        output
      }) => ({
        commandSummary,
        executable,
        args,
        cwd,
        exitCode,
        durationMs,
        timedOut,
        output
      }))
    });
    status = String(recorded.status ?? "");
    if (failed) {
      if (failed.output.trim()) workerLog(failed.output);
      const reason = formatVerificationFailure(failed);
      await mcp.callJson("dispatch_block_agent_session", {
        workerToken: job.workerToken,
        sessionId,
        reason
      });
      return { ok: false, error: reason };
    }
  }
  if (!["validated", "committing", "committed", "finalized"].includes(status)) {
    return { ok: false, error: `pending \u72B6\u6001\u65E0\u6CD5\u6062\u590D\uFF1A${status || "\u672A\u77E5"}` };
  }
  const finalized = await mcp.callJson("dispatch_finalize", {
    workerToken: job.workerToken,
    sessionId
  });
  if (finalized.preservePending === true) {
    return {
      ok: false,
      preservePending: true,
      error: String(
        finalized.error ?? "Git \u63D0\u4EA4\u540E\u5DE5\u4F5C\u533A\u4E0D\u5E72\u51C0\uFF0C\u62D2\u7EDD\u66F4\u65B0\u770B\u677F"
      )
    };
  }
  if (finalized.status !== "finalized" || String(finalized.sessionId ?? "") !== sessionId || String(finalized.cardId ?? "") !== cardId) {
    return { ok: false, error: `dispatch_finalize \u8FD4\u56DE\u72B6\u6001\u4E0D\u4E00\u81F4\uFF1A${sessionId}` };
  }
  return { ok: true };
}
function parseVerificationCommands(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.map((item) => {
    const record = asRecord3(item);
    if (!record) throw new Error("verificationCommands \u683C\u5F0F\u65E0\u6548");
    return {
      executable: requiredString(record, "executable"),
      args: parseStringArray(record.args, "verificationCommands.args"),
      cwd: String(record.cwd ?? ".").trim() || ".",
      expectedExitCode: Number(record.expectedExitCode ?? 0),
      ...Number.isFinite(record.timeoutMs) ? { timeoutMs: Number(record.timeoutMs) } : {}
    };
  });
}
function parseStringArray(raw, field) {
  if (!Array.isArray(raw) || raw.some((item) => typeof item !== "string")) {
    throw new Error(`\u534F\u8BAE\u5B57\u6BB5 ${field} \u5FC5\u987B\u662F\u5B57\u7B26\u4E32\u6570\u7EC4`);
  }
  return [...raw];
}
async function recordRoundFailure(mcp, job, sessionId, reason, block = false) {
  await mcp.callJson(
    block ? "dispatch_block_agent_session" : "dispatch_fail_agent_session",
    {
      workerToken: job.workerToken,
      sessionId,
      reason
    }
  ).catch((error) => {
    workerLog(
      `[warning] \u8BB0\u5F55\u4F1A\u8BDD\u5931\u8D25\u72B6\u6001\u5931\u8D25\uFF1A${error instanceof Error ? error.message : String(error)}`
    );
  });
}
function assertSessionMatches(status, sessionId, cardId) {
  if (status.sessionOpen !== true || status.pickClaimed !== true || String(status.sessionId ?? "") !== sessionId || String(status.cardId ?? "") !== cardId) {
    throw new Error(`Agent \u4F1A\u8BDD\u72B6\u6001\u4E0E claim \u4E0D\u4E00\u81F4\uFF1A${sessionId}/${cardId}`);
  }
}
function cardState(card) {
  const columnId = String(card.columnId ?? "");
  const columnName = String(card.columnName ?? "");
  if (columnId === "verify" || columnName === "\u5F85\u9A8C\u8BC1") return "verify";
  if (columnId === "blocked" || columnName === "\u963B\u585E\u4E2D") return "blocked";
  return "active";
}
function gitPreflightError(tree) {
  if (tree.kind === "dirty") {
    return `\u5DE5\u4F5C\u533A\u4E0D\u5E72\u51C0\uFF0C\u672A\u9886\u53D6\u5361\u7247\uFF1A
${tree.output}`;
  }
  if (tree.kind === "unknown") {
    return `\u65E0\u6CD5\u5224\u65AD Git \u5DE5\u4F5C\u533A\uFF0C\u672A\u9886\u53D6\u5361\u7247\uFF1A${tree.output}`;
  }
  return void 0;
}
function requiredString(record, key) {
  const value = String(record[key] ?? "").trim();
  if (!value) throw new Error(`\u534F\u8BAE\u5B57\u6BB5 ${key} \u4E0D\u80FD\u4E3A\u7A7A`);
  return value;
}
function asRecord3(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}
function completedResult(processedCards, reason) {
  workerLog(`[success] Worker \u6279\u6B21\u5B8C\u6210\uFF1A${reason}\uFF1B\u5DF2\u5904\u7406 ${processedCards} \u5F20`);
  return {
    ok: true,
    summary: `Worker \u6279\u6B21\u5B8C\u6210\uFF1A${reason}\uFF1B\u5DF2\u5904\u7406 ${processedCards} \u5F20`,
    processedCards
  };
}
function logModelOverride(original, round, cardId) {
  if (round.engine === original.engine && round.model === original.model && JSON.stringify(round.modelParams ?? []) === JSON.stringify(original.modelParams ?? [])) {
    return;
  }
  workerLog(
    `\u672C\u5361\u8986\u76D6\uFF1Aengine=${round.engine} model=${round.model ?? "(\u5E73\u53F0\u9ED8\u8BA4)"} params=${JSON.stringify(round.modelParams ?? [])} cardId=${cardId}`
  );
}

// src/cli.ts
function sleep(ms) {
  return new Promise((resolve3) => setTimeout(resolve3, ms));
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
  writeFileSync4(outPath, JSON.stringify(result, null, 2), "utf8");
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
async function listModels(engine) {
  if (engine === "codex") {
    try {
      const models2 = await listCodexModels(resolveCodexCommand());
      process.stdout.write(`${JSON.stringify({ models: models2 })}
`);
    } catch (err) {
      console.error(`Codex model/list \u5931\u8D25\uFF1A${err instanceof Error ? err.message : String(err)}`);
      process.exitCode = 2;
    }
    return;
  }
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
  const job = JSON.parse(readFileSync3(jobPath, "utf8"));
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
  const cancellation = new WorkerCancellation();
  cancellation.installSignalHandlers();
  if (job.cancelFile?.trim()) {
    cancellation.watchCancelFile(job.cancelFile.trim());
  }
  if (job.drainFile?.trim()) {
    cancellation.watchDrainFile(job.drainFile.trim());
  }
  if (job.skipFile?.trim()) {
    cancellation.watchSkipFile(job.skipFile.trim());
  }
  let result;
  try {
    result = await runBatch(job, cancellation);
  } catch (err) {
    if (err instanceof WorkerCancelledError) {
      result = { ok: false, error: err.message };
    } else {
      const message = err instanceof Error ? err.message : String(err);
      result = { ok: false, error: message };
    }
  } finally {
    cancellation.dispose();
  }
  writeResult(job.outPath, result);
  const code = result.ok ? 0 : 2;
  process.exitCode = code;
  process.exit(code);
}
async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes("--list-models")) {
    const engine = argv[argv.indexOf("--list-models") + 1] === "codex" ? "codex" : "cursor";
    await listModels(engine);
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
  await runJob(resolve2(argv[idx + 1]));
}
main().catch((err) => {
  console.error(err);
  process.exit(1);
});
