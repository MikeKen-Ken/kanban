// src/cli.ts
import { readFileSync as readFileSync8, writeFileSync as writeFileSync5 } from "node:fs";
import { resolve } from "node:path";
import { Cursor as Cursor3 } from "@cursor/sdk";

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

// src/types.ts
function applyLiveJobOverlay(job, live) {
  if (!live) return job;
  return {
    ...job,
    engine: parseEngine(live.engine, job.engine),
    model: typeof live.model === "string" ? live.model : job.model,
    modelParams: Array.isArray(live.modelParams) ? live.modelParams : job.modelParams,
    engineDefaults: live.engineDefaults ?? job.engineDefaults,
    ignoreCardParams: typeof live.ignoreCardParams === "boolean" ? live.ignoreCardParams : job.ignoreCardParams,
    allowDirtyWorkspace: typeof live.allowDirtyWorkspace === "boolean" ? live.allowDirtyWorkspace : job.allowDirtyWorkspace,
    enableSandbox: typeof live.enableSandbox === "boolean" ? live.enableSandbox : job.enableSandbox
  };
}
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
  if (isContextParamId(id)) {
    if (allowed.includes("64k")) return "64k";
    return allowed.length === 0 ? "64k" : middle;
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
function parameterValueList(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    if (typeof item === "string" && item.trim()) return [item.trim()];
    if (item && typeof item === "object" && "value" in item) {
      const text = String(item.value ?? "").trim();
      return text ? [text] : [];
    }
    return [];
  });
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
  if (job.ignoreCardParams === true) return job;
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
  const rawParameters = catalog?.parameters ?? [];
  const parameters = ensureContextParameter(rawParameters);
  const fillFrom = engine === "cursor" ? rawParameters : parameters;
  if (rawParameters.length > 0) {
    const allowed = new Set(
      fillFrom.map((item) => String(item.id ?? "").trim()).filter(Boolean)
    );
    for (const id of [...byId.keys()]) {
      if (!allowed.has(id)) byId.delete(id);
    }
    for (const parameter of fillFrom) {
      const id = String(parameter.id ?? "").trim();
      if (!id || byId.has(id)) continue;
      const value = conservativeParamValue(id, parameterValueList(parameter.values));
      if (value) byId.set(id, { id, value });
    }
  } else if (cardModel && engine === "codex") {
    const hasReasoning = [...byId.keys()].some(isReasoningParamId);
    if (!hasReasoning) {
      byId.set("reasoning_effort", { id: "reasoning_effort", value: "medium" });
    }
  }
  return {
    ...job,
    engine,
    model,
    modelParams: [...byId.values()],
    allowDirtyWorkspace: job.allowDirtyWorkspace === true || isTrueFlag(claim.agentAllowDirtyWorkspace),
    enableSandbox: job.enableSandbox === true || isTrueFlag(claim.agentEnableSandbox)
  };
}
function isTrueFlag(raw) {
  if (raw === true) return true;
  if (typeof raw !== "string") return false;
  return raw.trim().toLowerCase() === "true";
}
function isContextParamId(id) {
  return id.toLowerCase().includes("context");
}
var DEFAULT_CONTEXT_VALUES = ["64k", "272k"];
function contextCatalogParameter() {
  return {
    id: "context",
    displayName: "\u4E0A\u4E0B\u6587",
    values: DEFAULT_CONTEXT_VALUES.map((value) => ({
      value,
      displayName: value
    }))
  };
}
function ensureContextParameter(parameters) {
  if (parameters.some((item) => isContextParamId(String(item.id ?? "")))) {
    return parameters;
  }
  return [
    ...parameters,
    {
      id: "context",
      displayName: "\u4E0A\u4E0B\u6587",
      values: [...DEFAULT_CONTEXT_VALUES]
    }
  ];
}
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
function cursorCatalogParameterIds(job) {
  const modelId = job.model?.trim() || "composer-2.5";
  const catalog = job.engineDefaults?.cursor?.models?.find(
    (item) => item.id === modelId
  );
  return (catalog?.parameters ?? []).map((item) => String(item.id ?? "").trim()).filter((id) => id.length > 0 && !isContextParamId(id));
}
function cursorModelLikelySupportsFast(modelId) {
  return /composer/i.test(modelId.trim());
}
function withCursorSdkCatalog(job, models) {
  if (!models || models.length === 0) return job;
  return {
    ...job,
    engineDefaults: {
      ...job.engineDefaults,
      cursor: {
        ...job.engineDefaults?.cursor,
        models
      }
    }
  };
}
function errorLooksLikeUnsupportedParam(text) {
  return /not supported|unsupported|unknown param|invalid param|unrecognized param/i.test(
    text
  );
}
function nextCursorSdkParamsAfterCreateError(params, err) {
  if (!params || params.length === 0) {
    return { changed: false, params, dropped: [] };
  }
  const text = err instanceof Error ? err.message : String(err);
  if (!errorLooksLikeUnsupportedParam(text)) {
    return { changed: false, params, dropped: [] };
  }
  const lower = text.toLowerCase();
  const named = params.filter((item) => lower.includes(item.id.toLowerCase()));
  const dropped = named.length > 0 ? named.map((item) => item.id) : params.map((item) => item.id);
  const drop = new Set(dropped);
  const kept = params.filter((item) => !drop.has(item.id));
  return {
    changed: true,
    params: kept.length > 0 ? kept : void 0,
    dropped: [...new Set(dropped)]
  };
}
function selectCursorSdkModelParams(job) {
  const raw = resolveModelParams(job) ?? [];
  const modelId = job.model?.trim() || "composer-2.5";
  const catalogIds = cursorCatalogParameterIds(job);
  const allowed = new Set(catalogIds);
  const hasFast = raw.some((item) => item.id === "fast");
  const dropped = [];
  const kept = [];
  for (const item of raw) {
    if (isContextParamId(item.id)) {
      dropped.push(item.id);
      continue;
    }
    if (allowed.size > 0 && !allowed.has(item.id)) {
      dropped.push(item.id);
      continue;
    }
    if (allowed.size === 0 && item.id === "fast" && !cursorModelLikelySupportsFast(modelId)) {
      dropped.push(item.id);
      continue;
    }
    if (allowed.size === 0 && hasFast && isReasoningParamId(item.id) && cursorModelLikelySupportsFast(modelId)) {
      dropped.push(item.id);
      continue;
    }
    kept.push(item);
  }
  return {
    params: kept.length > 0 ? kept : void 0,
    dropped: [...new Set(dropped)]
  };
}
function effortToCodexConfigArgs(job) {
  const params = resolveModelParams(job) ?? [];
  const args = [];
  const effort = params.find(
    (p) => p.id === "reasoning_effort" || p.id === "model_reasoning_effort"
  );
  if (effort) {
    args.push("-c", `model_reasoning_effort=${effort.value}`);
  } else if (params.some((p) => p.id === "fast" && p.value === "true")) {
    args.push("-c", "model_reasoning_effort=low");
  }
  const context = params.find((item) => isContextParamId(item.id));
  if (context) {
    const tokens = parseTokenBudget(context.value);
    if (tokens != null) {
      args.push("-c", `model_context_window=${tokens}`);
    }
  }
  return args;
}

// src/codex_models.ts
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
  const effortParameter = efforts.length === 0 ? [] : [{
    id: "model_reasoning_effort",
    displayName: "\u63A8\u7406\u7A0B\u5EA6",
    values: efforts
  }];
  return {
    id,
    displayName: model.displayName,
    description: model.description,
    parameters: [
      ...effortParameter,
      ...effortParameter.some((item) => isContextParamId(item.id)) ? [] : [contextCatalogParameter()]
    ],
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
    const promise = new Promise((resolve2, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} \u8BF7\u6C42\u8D85\u65F6`));
      }, 15e3);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timeout);
          resolve2(value);
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

// src/retry.ts
var RETRYABLE_STATUS_CODES = /* @__PURE__ */ new Set([408, 425, 429, 500, 502, 503, 504]);
var RETRYABLE_ERROR_CODES = /* @__PURE__ */ new Set([
  "deadline_exceeded",
  "econnaborted",
  "econnrefused",
  "econnreset",
  "enetdown",
  "enetreset",
  "enetunreach",
  "etimedout",
  "resource_exhausted",
  "socket_closed",
  "und_err_connect_timeout",
  "unavailable"
]);
var RETRYABLE_MESSAGE_PARTS = [
  "connect timeout",
  "connection closed",
  "connection error",
  "connection failed",
  "connection lost",
  "connection reset",
  "fetch failed",
  "gateway timeout",
  "internal server error",
  "network",
  "overloaded",
  "remote host closed",
  "server error",
  "service unavailable",
  "socket hang up",
  "temporarily unavailable",
  "timed out",
  "timeout"
];
function sleep(ms) {
  return new Promise((resolve2) => setTimeout(resolve2, ms));
}
function isRetryableError(error) {
  if (error == null) return false;
  if (typeof error === "string") return retryableText(error);
  if (typeof error !== "object") return false;
  const record = error;
  if (record.isRetryable === true) return true;
  const status = Number(record.status ?? record.statusCode);
  if (Number.isFinite(status) && RETRYABLE_STATUS_CODES.has(status)) return true;
  const code = String(record.code ?? "").trim().toLowerCase();
  if (RETRYABLE_ERROR_CODES.has(code)) return true;
  const message = error instanceof Error ? error.message : String(record.message ?? "");
  if (retryableText(message)) return true;
  return "cause" in record && record.cause != null ? isRetryableError(record.cause) : false;
}
async function withRetry(operation, fn, options = {}) {
  const maxAttempts = Math.max(1, Math.trunc(options.maxAttempts ?? 3));
  const baseDelayMs = Math.max(0, Math.trunc(options.baseDelayMs ?? 1e3));
  const wait = options.sleep ?? sleep;
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt >= maxAttempts || !isRetryableError(error)) throw error;
      const delayMs = baseDelayMs * 2 ** (attempt - 1);
      options.onRetry?.({
        operation,
        attempt,
        maxAttempts,
        delayMs,
        error
      });
      await wait(delayMs);
    }
  }
  throw lastError;
}
function retryableText(value) {
  const lower = value.toLowerCase();
  return RETRYABLE_MESSAGE_PARTS.some((part) => lower.includes(part)) || [...RETRYABLE_ERROR_CODES].some((code) => lower.includes(code));
}

// src/run_codex.ts
import { spawn as spawn2 } from "node:child_process";
import {
  existsSync as existsSync4,
  mkdtempSync as mkdtempSync2,
  readFileSync as readFileSync3,
  rmSync as rmSync2,
  writeFileSync as writeFileSync3
} from "node:fs";
import { tmpdir as tmpdir2 } from "node:os";
import { dirname, join as join3 } from "node:path";
import { fileURLToPath } from "node:url";

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
function formatSessionTokenLog(raw, diagnostics) {
  const usage = toDashboardTokenUsage(raw);
  return `\u672C\u4F1A\u8BDD token\uFF1Ainput=${usage.inputTokens} output=${usage.outputTokens} cacheRead=${usage.cacheReadTokens} cacheWrite=${usage.cacheWriteTokens} total=${usage.totalTokens}` + (diagnostics ? ` steps=${diagnostics.steps} tools=${diagnostics.toolCalls} repeatedToolCalls=${diagnostics.repeatedToolCalls} repeatedReads=${diagnostics.repeatedReads}` : "");
}

// src/assistant_text.ts
function extractAssistantText(value) {
  const chunks = [];
  collectText(value, chunks, 0);
  return chunks.join("").trim();
}
function extractCursorAssistantStepText(step) {
  const record = asRecord2(step);
  if (!record) return "";
  const type = String(record.type ?? "");
  if (type && type !== "assistantMessage" && type !== "assistant") return "";
  return extractAssistantText(record.message ?? record);
}
function extractCursorThinkingStepText(step) {
  const record = asRecord2(step);
  if (!record) return "";
  const type = String(record.type ?? "");
  const message = asRecord2(record.message) ?? record;
  if (type && type !== "thinkingMessage" && type !== "thinking" && type !== "reasoning") {
    if (typeof message.thinking !== "string" && typeof message.thinkingDurationMs !== "number") {
      return "";
    }
  }
  return extractThinkingText(record.message ?? record);
}
function extractCodexAssistantEventText(event) {
  const message = extractCodexTranscriptMessage(event);
  return message?.role === "assistant" ? message.text : "";
}
function extractCodexTranscriptMessage(event) {
  const record = asRecord2(event);
  if (!record) return void 0;
  const type = String(record.type ?? "");
  const item = asRecord2(record.item) ?? {};
  const itemType = String(item.type ?? item.item_type ?? "");
  const role = String(item.role ?? "");
  if (itemType === "reasoning" || itemType === "thinking") {
    if (type !== "item.completed" && type !== "item.updated") return void 0;
    const thinking = extractThinkingText(item);
    return thinking ? { role: "thinking", text: thinking } : void 0;
  }
  if (type !== "item.completed") return void 0;
  if (itemType === "user_message" || itemType === "user" || itemType === "message" && role === "user") {
    const text = extractAssistantText(item);
    return text ? { role: "user", text } : void 0;
  }
  if (itemType === "agent_message" || itemType === "assistant_message" || itemType === "message" && (role === "assistant" || role === "agent")) {
    const text = extractAssistantText(item);
    return text ? { role: "assistant", text } : void 0;
  }
  return void 0;
}
function extractConversationMessages(turns) {
  const messages = [];
  if (!Array.isArray(turns)) return messages;
  for (const turn of turns) {
    const record = asRecord2(turn);
    if (!record) continue;
    const inner = asRecord2(record.turn) ?? record;
    const userText = extractUserText(inner.userMessage ?? record.userMessage);
    if (userText) messages.push({ role: "user", text: userText });
    const steps = inner.steps ?? record.steps;
    if (!Array.isArray(steps)) continue;
    for (const step of steps) {
      const thinking = extractCursorThinkingStepText(step);
      if (thinking) {
        messages.push({ role: "thinking", text: thinking });
        continue;
      }
      const assistant = extractCursorAssistantStepText(step);
      if (assistant) messages.push({ role: "assistant", text: assistant });
    }
  }
  return messages;
}
function extractThinkingText(value) {
  if (typeof value === "string") return value.trim();
  const record = asRecord2(value);
  if (!record) return "";
  for (const key of ["thinking", "text"]) {
    const field = record[key];
    if (typeof field === "string" && field.trim()) return field.trim();
  }
  const content = record.content;
  if (Array.isArray(content)) {
    const parts = content.map((item) => {
      if (typeof item === "string") return item.trim();
      const inner = asRecord2(item);
      if (!inner) return "";
      const innerType = String(inner.type ?? "");
      if (innerType && innerType !== "thinking" && innerType !== "reasoning" && innerType !== "reasoning_text" && innerType !== "text") {
        return "";
      }
      return extractThinkingText(inner);
    }).filter((part) => part.length > 0);
    if (parts.length > 0) return parts.join("\n").trim();
  }
  if (typeof content === "string" && content.trim()) return content.trim();
  return extractAssistantText(record);
}
function extractUserText(value) {
  if (typeof value === "string") return value.trim();
  const record = asRecord2(value);
  if (!record) return "";
  if (typeof record.text === "string" && record.text.trim()) {
    return record.text.trim();
  }
  return extractAssistantText(record);
}
function collectText(value, chunks, depth) {
  if (depth > 6 || value == null) return;
  if (typeof value === "string") {
    if (value.trim()) chunks.push(value);
    return;
  }
  if (typeof value !== "object") return;
  if (Array.isArray(value)) {
    for (const item of value) collectText(item, chunks, depth + 1);
    return;
  }
  const record = value;
  const type = String(record.type ?? "");
  if (type === "tool_use" || type === "tool-use" || type === "toolCall") return;
  if (typeof record.text === "string" && record.text.trim()) {
    chunks.push(record.text);
    return;
  }
  if (typeof record.thinking === "string" && type === "thinking") return;
  if (record.content !== void 0) {
    collectText(record.content, chunks, depth + 1);
    return;
  }
  if (record.parts !== void 0) {
    collectText(record.parts, chunks, depth + 1);
    return;
  }
  if (record.message !== void 0) {
    collectText(record.message, chunks, depth + 1);
  }
}
function asRecord2(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}

// src/codex_exec_log.ts
var OUTPUT_CLIP = 4e3;
var JSON_CLIP = 2e3;
var ANSI_PATTERN = /\x1B\[[0-9;]*m/g;
var DIAGNOSTIC_PATTERN = /^\s*(?:warning:|error:|fatal:|WARN\b|ERROR\b|FATAL\b)/i;
var RECONNECT_PATTERN = /reconnecting\.\.\.\s*\d+\s*\/\s*\d+/i;
function createCodexLogState() {
  return {
    jsonSeen: false,
    ttyRole: "none",
    ttyExecAwaitingCommand: false,
    ttyAwaitingTokenCount: false
  };
}
function createLineBuffer(onLine) {
  let pending = "";
  return {
    push(chunk) {
      pending += typeof chunk === "string" ? chunk : chunk.toString("utf8");
      pending = pending.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
      let index = pending.indexOf("\n");
      while (index >= 0) {
        onLine(pending.slice(0, index));
        pending = pending.slice(index + 1);
        index = pending.indexOf("\n");
      }
    },
    flush() {
      if (pending.length > 0) onLine(pending);
      pending = "";
    }
  };
}
function recordsFromCodexJsonLine(raw, state) {
  const line = stripAnsi(raw).trim();
  if (!line) return [];
  if (!line.startsWith("{")) {
    return recordsFromCodexStderrLine(line, state);
  }
  let event;
  try {
    event = asRecord3(JSON.parse(line)) ?? {};
  } catch {
    return withDefaultLevel([{ line: clip(line, 200), source: "worker" }]);
  }
  state.jsonSeen = true;
  return recordsFromCodexEvent(event);
}
function recordsFromCodexStderrLine(raw, state) {
  const line = stripAnsi(raw).replace(/\s+$/, "");
  if (!line.trim()) return [];
  const diagnostic = diagnosticRecord(line, "worker");
  if (state.jsonSeen) return withDefaultLevel(diagnostic ? [diagnostic] : []);
  return withDefaultLevel(recordsFromCodexTtyLine(line, state));
}
function recordsFromCodexEvent(event) {
  return withDefaultLevel(recordsFromCodexEventInner(event));
}
function recordsFromCodexEventInner(event) {
  const type = String(event.type ?? "");
  switch (type) {
    case "thread.started": {
      const threadId = pickString(event, "thread_id");
      return threadId ? [{ line: `Codex \u4F1A\u8BDD ${threadId}`, source: "worker" }] : [];
    }
    case "turn.started":
      return [];
    case "turn.completed":
      return recordsFromUsage(asRecord3(event.usage));
    case "turn.failed": {
      const message = pickString(asRecord3(event.error), "message") || pickString(event, "message") || "Codex \u56DE\u5408\u5931\u8D25";
      return [{ line: message, source: "worker", level: "error" }];
    }
    case "error": {
      const message = pickString(event, "message") || "Codex \u9519\u8BEF";
      if (RECONNECT_PATTERN.test(message)) {
        return [{ line: message, source: "worker" }];
      }
      return [{ line: message, source: "worker", level: "error" }];
    }
    case "item.started":
    case "item.updated":
    case "item.completed":
      return recordsFromCodexItem(type, asRecord3(event.item) ?? {});
    default:
      return [];
  }
}
function recordsFromCodexItem(eventType, item) {
  const itemType = String(item.type ?? item.item_type ?? "");
  const status = String(item.status ?? "");
  const failed = status === "failed" || eventType === "item.failed";
  switch (itemType) {
    case "agent_message":
    case "assistant_message":
      if (eventType !== "item.completed") return [];
      return toRecords(
        expandMultiline("\u52A9\u624B\uFF1A", extractAssistantText(item) || pickString(item, "text")),
        "ai"
      );
    case "reasoning":
      if (eventType !== "item.completed") return [];
      return toRecords(expandMultiline("\u601D\u8003\uFF1A", pickString(item, "text")), "ai");
    case "command_execution":
      return recordsFromCommand(
        eventType,
        item,
        commandExecutionFailed(eventType, item, status)
      );
    case "file_change":
      if (eventType !== "item.completed") return [];
      return recordsFromFileChange(item, failed);
    case "mcp_tool_call":
      return recordsFromMcp(eventType, item, failed);
    case "web_search":
      if (eventType !== "item.completed") return [];
      return pickString(item, "query") ? [{ line: `\u5DE5\u5177\uFF1Aweb_search ${pickString(item, "query")}`, source: "mcp" }] : [];
    case "todo_list":
      return recordsFromTodo(item);
    case "error":
      if (eventType !== "item.completed") return [];
      return [
        {
          line: pickString(item, "message") || "Codex \u975E\u81F4\u547D\u8B66\u544A",
          source: "worker",
          level: "warning"
        }
      ];
    default:
      return [];
  }
}
function commandExecutionFailed(eventType, item, status) {
  if (eventType === "item.failed") return true;
  const exitCode = item.exit_code;
  if (typeof exitCode === "number" && Number.isFinite(exitCode)) {
    return exitCode !== 0;
  }
  return status === "failed";
}
function recordsFromCommand(eventType, item, failed) {
  const command = pickString(item, "command");
  if (eventType === "item.started") {
    return command ? toRecords(expandMultiline("\u547D\u4EE4\uFF1A", command), "shell") : [];
  }
  if (eventType !== "item.completed") return [];
  const records = [];
  if (command && failed) {
    records.push({
      line: `\u547D\u4EE4\u5931\u8D25\uFF1A${clip(command, JSON_CLIP)}`,
      source: "shell",
      level: "error"
    });
  }
  const output = pickString(item, "aggregated_output");
  if (failed && output.trim()) {
    records.push(
      ...toRecords(expandMultiline("\u547D\u4EE4\u8F93\u51FA\uFF1A", clip(output, OUTPUT_CLIP)), "shell", "error")
    );
  }
  records.push(...diagnosticRecordsFromOutput(output, "shell"));
  return records;
}
function recordsFromFileChange(item, failed) {
  const changes = Array.isArray(item.changes) ? item.changes : [];
  const parts = changes.map((entry) => asRecord3(entry)).filter((entry) => entry != null).map((entry) => {
    const path = pickString(entry, "path");
    if (!path) return "";
    const kind = String(entry.kind ?? "update");
    const label = kind === "add" ? "\u65B0\u589E" : kind === "delete" ? "\u5220\u9664" : "\u66F4\u65B0";
    return `${label} ${path}`;
  }).filter(Boolean);
  const detail = parts.join("\uFF1B") || "apply_patch";
  return [
    {
      line: `\u5DE5\u5177\uFF1Aapply_patch ${detail}`,
      source: "mcp",
      level: failed ? "error" : "info"
    }
  ];
}
function recordsFromMcp(eventType, item, failed) {
  const tool = pickString(item, "tool") || "tool";
  if (eventType === "item.started") {
    const args = usefulJson(item.arguments);
    const detail = args ? `${tool} ${args}` : `${tool} \u5F00\u59CB`;
    return [{ line: `\u5DE5\u5177\uFF1A${detail}`, source: "mcp" }];
  }
  if (eventType !== "item.completed") return [];
  if (failed) {
    const err = pickString(asRecord3(item.error), "message") || pickString(item, "error") || "\u8C03\u7528\u5931\u8D25";
    return [
      {
        line: `\u5DE5\u5177\u5931\u8D25\uFF1A${tool} ${err}`,
        source: "mcp",
        level: "error"
      }
    ];
  }
  const result = mcpResultText(item.result);
  if (!result.trim()) return [];
  return toRecords(expandMultiline(`\u5DE5\u5177\u7ED3\u679C\uFF1A${tool} `, result), "mcp");
}
function recordsFromTodo(item) {
  const items = Array.isArray(item.items) ? item.items : [];
  const parts = items.map((entry) => asRecord3(entry)).filter((entry) => entry != null).map((entry) => {
    const text = pickString(entry, "text");
    if (!text) return "";
    return `${entry.completed === true ? "\u2713 " : ""}${text}`;
  }).filter(Boolean);
  if (parts.length === 0) return [];
  return [{ line: `\u8BA1\u5212\uFF1A${parts.join("\uFF1B")}`, source: "worker" }];
}
function recordsFromUsage(usage) {
  if (!usage) return [];
  const cached = asCount2(usage.cached_input_tokens);
  const inputRaw = asCount2(usage.input_tokens);
  const input = cached > 0 && inputRaw >= cached ? inputRaw - cached : inputRaw;
  const output = asCount2(usage.output_tokens);
  if (input + output + cached <= 0) return [];
  return [
    {
      line: formatSessionTokenLog({
        inputTokens: input,
        outputTokens: output,
        cacheReadTokens: cached
      }),
      source: "worker"
    }
  ];
}
function recordsFromCodexTtyLine(line, state) {
  const trimmed = line.trim();
  const role = ttyRoleOf(trimmed);
  if (role) {
    state.ttyRole = role;
    state.ttyExecAwaitingCommand = role === "exec";
    state.ttyAwaitingTokenCount = trimmed === "tokens used";
    if (trimmed.startsWith("mcp:")) return recordsFromTtyMcp(trimmed);
    if (trimmed === "apply patch") {
      return [{ line: "\u5DE5\u5177\uFF1Aapply_patch", source: "mcp" }];
    }
    if (trimmed === "patch: completed") {
      return [{ line: "\u5DE5\u5177\u7ED3\u679C\uFF1Aapply_patch", source: "mcp" }];
    }
    if (trimmed === "tokens used") return [];
    return [];
  }
  if (state.ttyAwaitingTokenCount) {
    state.ttyAwaitingTokenCount = false;
    const total = Number(trimmed.replace(/,/g, ""));
    if (Number.isFinite(total) && total > 0) {
      return [{ line: `Codex tokens used\uFF1A${trimmed}`, source: "worker" }];
    }
  }
  if (isBannerLine(trimmed)) {
    return [{ line: trimmed, source: "worker" }];
  }
  if (state.ttyRole === "user") return [];
  if (state.ttyRole === "codex") {
    return toRecords(expandMultiline("\u52A9\u624B\uFF1A", line), "ai");
  }
  if (state.ttyRole === "exec") {
    if (state.ttyExecAwaitingCommand) {
      state.ttyExecAwaitingCommand = false;
      return toRecords(expandMultiline("\u547D\u4EE4\uFF1A", trimmed), "shell");
    }
    if (/^failed in /i.test(trimmed) || /^error in /i.test(trimmed)) {
      return [{ line: `\u547D\u4EE4\u5931\u8D25\uFF1A${trimmed}`, source: "shell", level: "error" }];
    }
    const diagnostic2 = diagnosticRecord(trimmed, "shell");
    return diagnostic2 ? [diagnostic2] : [];
  }
  if (state.ttyRole === "patch") {
    if (trimmed.startsWith("diff ") || trimmed.startsWith("index ")) return [];
    if (/^[+-]/.test(trimmed) || trimmed.startsWith("@@")) return [];
    if (/^[A-Za-z]:\\/.test(trimmed) || trimmed.includes("/")) {
      return [{ line: `\u5DE5\u5177\u7ED3\u679C\uFF1Aapply_patch ${trimmed}`, source: "mcp" }];
    }
    return [];
  }
  const diagnostic = diagnosticRecord(trimmed, "worker");
  if (diagnostic) return [diagnostic];
  return [{ line: trimmed, source: "worker" }];
}
function ttyRoleOf(trimmed) {
  if (trimmed === "user") return "user";
  if (trimmed === "codex") return "codex";
  if (trimmed === "exec") return "exec";
  if (trimmed === "apply patch" || trimmed === "patch: completed") return "patch";
  if (trimmed === "tokens used") return "none";
  if (trimmed.startsWith("mcp:")) return "none";
  return void 0;
}
function recordsFromTtyMcp(line) {
  const match = /^mcp:\s*([^/]+)\/(\S+)\s+(started|\(completed\))$/.exec(line);
  if (!match) return [{ line: `\u5DE5\u5177\uFF1A${line.slice(4).trim()}`, source: "mcp" }];
  const tool = match[2];
  if (match[3] === "started") {
    return [{ line: `\u5DE5\u5177\uFF1A${tool} \u5F00\u59CB`, source: "mcp" }];
  }
  return [{ line: `\u5DE5\u5177\u7ED3\u679C\uFF1A${tool} \u5B8C\u6210`, source: "mcp" }];
}
function isBannerLine(line) {
  return line.startsWith("OpenAI Codex") || line === "--------" || /^(workdir|model|provider|approval|sandbox|reasoning effort|reasoning summaries|session id):/i.test(
    line
  );
}
function diagnosticRecordsFromOutput(output, source) {
  if (!output.trim()) return [];
  const records = [];
  const seen = /* @__PURE__ */ new Set();
  for (const line of output.split(/\r?\n/)) {
    const record = diagnosticRecord(stripAnsi(line), source);
    if (!record || seen.has(record.line)) continue;
    seen.add(record.line);
    records.push(record);
  }
  return records;
}
function withDefaultLevel(records) {
  return records.map((record) => ({
    ...record,
    level: record.level ?? "info"
  }));
}
function diagnosticRecord(line, source) {
  const trimmed = line.trim();
  if (!DIAGNOSTIC_PATTERN.test(trimmed)) return void 0;
  if (looksLikeDartNamedArgument(trimmed)) return void 0;
  const level = /^\s*(?:warning:|WARN\b)/i.test(trimmed) ? "warning" : "error";
  return { line: trimmed, source, level };
}
function looksLikeDartNamedArgument(line) {
  return /^\s*error:\s*(?:[A-Za-z_]\w*|'[^']*'|"[^"]*")\s*,?\s*$/.test(line);
}
function expandMultiline(prefix, body) {
  const lines = body.replace(/\s+$/, "").split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) {
    return prefix.endsWith(" ") || prefix.endsWith("\uFF1A") ? [] : [prefix];
  }
  const result = [`${prefix}${lines[0]}`];
  for (let i = 1; i < lines.length; i++) {
    result.push(`  \u2502 ${lines[i]}`);
  }
  return result;
}
function toRecords(lines, source, level = "info") {
  return lines.map((line) => ({ line, source, level }));
}
function mcpResultText(result) {
  const record = asRecord3(result);
  if (!record) return usefulJson(result);
  const content = record.content;
  if (Array.isArray(content)) {
    const texts = content.map((block) => asRecord3(block)).filter((block) => block != null).filter((block) => block.type === "text" && typeof block.text === "string").map((block) => String(block.text).trim()).filter(Boolean);
    if (texts.length > 0) return clip(texts.join("\n"), OUTPUT_CLIP);
  }
  return usefulJson(record.structured_content ?? result);
}
function usefulJson(value, max = JSON_CLIP) {
  if (value === void 0 || value === null) return "";
  if (typeof value === "string") return clip(value.trim(), max);
  try {
    const text = JSON.stringify(value);
    if (!text || text === "{}" || text === "[]" || text === "null") return "";
    return clip(text, max);
  } catch {
    return clip(String(value), max);
  }
}
function pickString(record, key) {
  const value = record?.[key];
  return typeof value === "string" ? value : "";
}
function asRecord3(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}
function asCount2(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.trunc(value));
}
function clip(text, max) {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}\u2026`;
}
function stripAnsi(text) {
  return text.replace(ANSI_PATTERN, "");
}

// src/codex_mcp.ts
import {
  copyFileSync,
  cpSync,
  existsSync as existsSync2,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  statSync,
  writeFileSync
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

// src/dispatch_mcp_allowlist.ts
var MCP_LABEL_SERVERS = {
  aseprite: ["aseprite"],
  "chrome-devtools": ["chrome-devtools"],
  chrome: ["chrome-devtools"],
  hub: ["hubMCP"],
  hubMCP: ["hubMCP"],
  tavily: ["tavily"],
  unity: ["unitymcp", "unityMCP"],
  cocos: ["cocos-creator"],
  node_repl: ["node_repl"]
};
function parseProjectMcpTags(payload) {
  const raw = payload.projectMcpTags;
  if (!Array.isArray(raw)) return [];
  const result = [];
  const seen = /* @__PURE__ */ new Set();
  for (const item of raw) {
    if (typeof item !== "string") continue;
    const label = item.trim();
    if (!label || seen.has(label)) continue;
    seen.add(label);
    result.push(label);
  }
  return result;
}
function allowedMcpServerNames(labels) {
  const allowed = /* @__PURE__ */ new Set();
  for (const raw of labels) {
    const key = raw.trim();
    if (!key) continue;
    const mapped = MCP_LABEL_SERVERS[key] ?? MCP_LABEL_SERVERS[key.toLowerCase()];
    if (mapped) {
      for (const name of mapped) allowed.add(name);
      continue;
    }
    allowed.add(key);
  }
  return allowed;
}
function mcpServerNameAllowed(serverName, allowed) {
  const name = serverName.trim();
  if (!name) return false;
  if (allowed.has(name)) return true;
  const lower = name.toLowerCase();
  for (const item of allowed) {
    if (item.toLowerCase() === lower) return true;
  }
  return false;
}
function filterRecordByMcpAllowlist(servers, labels) {
  const allowed = allowedMcpServerNames(labels);
  if (allowed.size === 0) return {};
  const result = {};
  for (const [name, value] of Object.entries(servers)) {
    if (mcpServerNameAllowed(name, allowed)) result[name] = value;
  }
  return result;
}

// src/codex_agent_config.ts
var KANBAN_TABLE = "mcp_servers.kanbanMCP";
function isKanbanMcpTable(name) {
  const table = name.trim();
  return table === KANBAN_TABLE || table.startsWith(`${KANBAN_TABLE}.`);
}
function ensureCodexRmcpClient(source) {
  if (/^\s*rmcp_client\s*=\s*true\s*$/m.test(source)) return source;
  const features = /^\[features\]\s*$/m.exec(source);
  if (features == null || features.index == null) {
    const trimmed = source.trimEnd();
    const block = "[features]\nrmcp_client = true\n";
    if (!trimmed) return block;
    return `${trimmed}

${block}`;
  }
  const insertAt = features.index + features[0].length;
  return `${source.slice(0, insertAt)}
rmcp_client = true${source.slice(insertAt)}`;
}
function filterCodexMcpTables(source, allowedServers) {
  const matches = [...source.matchAll(/^\[([^\]]+)\]/gm)];
  if (matches.length === 0) return source;
  const firstIndex = matches[0]?.index ?? 0;
  let result = source.slice(0, firstIndex);
  for (let index = 0; index < matches.length; index += 1) {
    const match = matches[index];
    const name = match[1] ?? "";
    const start = match.index ?? 0;
    const end = matches[index + 1]?.index ?? source.length;
    if (!shouldKeepTomlTable(name, allowedServers)) continue;
    result += source.slice(start, end);
  }
  return collapseBlankLines(result);
}
function buildCodexAgentConfigToml(mcpUrl, userConfig = "", projectMcpTags = []) {
  const url = mcpUrl.trim();
  const allowed = allowedMcpServerNames(projectMcpTags);
  const filtered = filterCodexMcpTables(userConfig, allowed);
  const withFeatures = ensureCodexRmcpClient(filtered);
  const block = `[mcp_servers.kanbanMCP]
url = "${url}"
`;
  const trimmed = withFeatures.trimEnd();
  if (!trimmed) {
    return `[features]
rmcp_client = true

${block}`;
  }
  return `${trimmed}

${block}`;
}
function shouldKeepTomlTable(table, allowed) {
  const name = table.trim();
  if (isKanbanMcpTable(name)) return false;
  const mcp = /^mcp_servers\.([^.]+)/.exec(name);
  if (mcp == null) return true;
  return mcpServerNameAllowed(mcp[1] ?? "", allowed);
}
function listCodexMcpServerNames(toml) {
  const names = [];
  const seen = /* @__PURE__ */ new Set();
  for (const match of toml.matchAll(/^\[mcp_servers\.([^\].]+)\]/gm)) {
    const name = match[1]?.trim();
    if (!name || seen.has(name)) continue;
    seen.add(name);
    names.push(name);
  }
  return names;
}
function collapseBlankLines(source) {
  return source.replace(/\n{3,}/g, "\n\n").replace(/^\n+/, "").trimEnd();
}

// src/dispatch_agents_overlay.ts
var DISPATCH_ARCHITECTURE_OVERRIDE = `# \u672C\u4F1A\u8BDD\u8986\u76D6\uFF08\u4EC5\u770B\u677F Agent \u8C03\u5EA6\uFF09

Worker \u5DF2\u6CE8\u5165\u76EE\u6807\u4ED3\u5E93 \`docs/Architecture.md\` \u5168\u6587\u3002\u7528\u6237\u89C4\u5219 / \`AGENTS.md\` \u91CC\u7684\u300C\u5F00\u53D1\u524D\u5FC5\u8BFB Architecture.md\u300D\u5728\u672C\u8F6E\u89C6\u4E3A\u5DF2\u6EE1\u8DB3\u3002
\u7981\u6B62\u518D\u641C\u7D22\u3001glob\u3001grep \u6216\u8BFB\u53D6 \`docs/Architecture.md\`\u3002ADR\u3001\`docs/Systems/\`\u3001\`CONTEXT.md\` \u4ECD\u6309\u539F\u6587\uFF0C\u9700\u8981\u65F6\u518D\u8BFB\u3002
`;
function applyDispatchArchitectureOverride(source) {
  const body = rewriteArchitectureFileReads(source.replaceAll("\r\n", "\n").trim());
  return `${DISPATCH_ARCHITECTURE_OVERRIDE.trim()}

${body}`.trim() + "\n";
}
function rewriteArchitectureFileReads(source) {
  if (!source) return "";
  return source.split("\n").filter((line) => !isArchitectureFileReadBullet(line)).join("\n").replace(
    /动手写代码[^\n]*MUST 先阅读：/,
    "\u52A8\u624B\u5199\u4EE3\u7801\u3001\u6539\u6A21\u5757\u8FB9\u754C\u6216\u8BBE\u8BA1\u65B9\u6848\u524D\uFF0C`docs/Architecture.md` \u5DF2\u7531 Worker \u6CE8\u5165\uFF0C\u89C6\u4E3A\u5DF2\u8BFB\uFF1B\u7981\u6B62\u518D\u6253\u5F00\u8BE5\u6587\u4EF6\u3002"
  ).replace(
    /MUST NOT 在未读 `Architecture\.md`（若存在）的情况下/,
    "MUST NOT \u5728\u672A\u9075\u5B88\u5DF2\u6CE8\u5165 Architecture.md \u7684\u60C5\u51B5\u4E0B"
  );
}
function isArchitectureFileReadBullet(line) {
  const trimmed = line.trim();
  if (!trimmed.startsWith("-") && !trimmed.startsWith("*")) return false;
  return trimmed.includes("docs/Architecture.md");
}

// src/codex_mcp.ts
var AUTH_FILES = ["auth.json"];
var USER_INSTRUCTION_DIRS = ["skills"];
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
  const userConfigPath = join(options.userCodexHome, "config.toml");
  const userConfig = existsSync2(userConfigPath) ? readFileSync(userConfigPath, "utf8") : "";
  const config = buildCodexAgentConfigToml(
    options.mcpUrl,
    userConfig,
    options.projectMcpTags ?? []
  );
  writeFileSync(join(home, "config.toml"), config, "utf8");
  for (const name of AUTH_FILES) {
    copyUserPath(
      join(options.userCodexHome, name),
      join(home, name)
    );
  }
  writeOverlayAgentsMarkdown(options.userCodexHome, home);
  for (const name of USER_INSTRUCTION_DIRS) {
    copyUserPath(
      join(options.userCodexHome, name),
      join(home, name)
    );
  }
  return { home, mcpServerNames: listCodexMcpServerNames(config) };
}
function writeOverlayAgentsMarkdown(userHome, destHome) {
  const from = join(userHome, "AGENTS.md");
  const source = existsSync2(from) ? readFileSync(from, "utf8") : "";
  const overlay = applyDispatchArchitectureOverride(source);
  writeFileSync(join(destHome, "AGENTS.md"), overlay, "utf8");
  writeFileSync(join(destHome, "AGENTS.override.md"), overlay, "utf8");
}
function copyUserPath(from, to) {
  if (!existsSync2(from)) return;
  if (statSync(from).isDirectory()) {
    cpSync(from, to, { recursive: true });
    return;
  }
  copyFileSync(from, to);
}

// src/dispatch_terminal.ts
var DISPATCH_TERMINAL_TOOL_NAMES = [
  "ready_to_submit",
  "submit_consultation",
  "block_card"
];
function asRecord4(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}
function pickString2(record, ...keys) {
  if (!record) return "";
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}
function toolPayload(step) {
  return asRecord4(step.message) ?? asRecord4(step.toolCall) ?? asRecord4(step.call) ?? asRecord4(step.tool) ?? asRecord4(asRecord4(step.message)?.toolCall) ?? asRecord4(asRecord4(step.message)?.call);
}
function dispatchTerminalToolName(step) {
  const record = asRecord4(step);
  if (!record) return void 0;
  const message = toolPayload(record);
  const nested = asRecord4(message?.args) ?? asRecord4(message?.arguments) ?? asRecord4(message?.input) ?? asRecord4(message?.params);
  const name = pickString2(message, "toolName", "name") || pickString2(nested, "toolName", "name");
  const type = pickString2(message, "type") || pickString2(record, "type");
  if (DISPATCH_TERMINAL_TOOL_NAMES.includes(name)) {
    return name;
  }
  if (type === "mcp") {
    const nestedName = pickString2(nested, "toolName", "name");
    if (DISPATCH_TERMINAL_TOOL_NAMES.includes(
      nestedName
    )) {
      return nestedName;
    }
  }
  return void 0;
}
function resultLooksFailed(result) {
  const status = String(result.status ?? "").toLowerCase();
  if (status === "error" || status === "failed") return true;
  if (result.isError === true) return true;
  const value = asRecord4(result.value) ?? result;
  if (value.ok === false) return true;
  return false;
}
function resultLooksSuccess(result) {
  if (resultLooksFailed(result)) return false;
  const status = String(result.status ?? "").toLowerCase();
  if (status === "success" || status === "ok" || status === "completed") {
    return true;
  }
  const value = asRecord4(result.value) ?? result;
  return value.ok === true;
}
function isSuccessfulDispatchTerminalStep(step) {
  if (!dispatchTerminalToolName(step)) return false;
  const record = asRecord4(step);
  const message = record ? toolPayload(record) : void 0;
  const result = asRecord4(message?.result) ?? asRecord4(message?.output);
  if (!result) return false;
  return resultLooksSuccess(result);
}
function startPollingDispatchTerminal(peek, onHit, intervalMs = 750) {
  if (!peek) return { stop() {
  } };
  let stopped = false;
  const tick = async () => {
    while (!stopped) {
      try {
        const kind = await peek();
        if (kind !== "none") {
          onHit(kind);
          return;
        }
      } catch {
      }
      await sleep(intervalMs);
    }
  };
  void tick();
  return {
    stop() {
      stopped = true;
    }
  };
}

// src/interaction_bridge.ts
import {
  existsSync as existsSync3,
  mkdirSync as mkdirSync2,
  readFileSync as readFileSync2,
  rmSync,
  writeFileSync as writeFileSync2,
  writeSync
} from "node:fs";
import { randomUUID } from "node:crypto";
import { join as join2 } from "node:path";
var INTERACTION_EVENT_PREFIX = "@@KANBAN_INTERACTION@@";
var interactionStdio = {
  write(line) {
    writeSync(1, line);
  }
};
function emitInteractionEvent(event) {
  interactionStdio.write(
    `${INTERACTION_EVENT_PREFIX}${JSON.stringify({
      ...event,
      at: (/* @__PURE__ */ new Date()).toISOString()
    })}
`
  );
}
function sessionStartText(job) {
  const items = workItems(job);
  return items.length === 0 ? "\u5F00\u59CB\u5904\u7406\u672C\u5361\u3002" : items.map((item) => `- ${item}`).join("\n");
}
function conversationSnapshotFileName(cardId) {
  return `conversation-snapshot-${cardId.replace(/[^a-zA-Z0-9._-]/g, "_")}.json`;
}
function writeConversationSnapshot(job, messages) {
  const interactionDir = job.interactionDir?.trim();
  if (!interactionDir || messages.length === 0) return void 0;
  mkdirSync2(interactionDir, { recursive: true });
  const fileName = conversationSnapshotFileName(job.round.cardId);
  writeFileSync2(
    join2(interactionDir, fileName),
    `${JSON.stringify({
      cardId: job.round.cardId,
      sessionId: job.round.sessionId,
      projectId: job.projectId,
      messages
    })}
`,
    "utf8"
  );
  return fileName;
}
function emitConversationSnapshot(job, messages) {
  const fileName = writeConversationSnapshot(job, messages);
  if (!fileName) return;
  emitInteractionEvent({
    type: "snapshot",
    projectId: job.projectId,
    cardId: job.round.cardId,
    sessionId: job.round.sessionId,
    text: fileName
  });
}
function emitSessionStart(job) {
  emitInteractionEvent({
    type: "session",
    projectId: job.projectId,
    cardId: job.round.cardId,
    sessionId: job.round.sessionId,
    text: sessionStartText(job)
  });
}
function emitAssistantMessage(job, text) {
  emitRoleMessage(job, "assistant", text);
}
function emitThinkingMessage(job, text) {
  emitRoleMessage(job, "thinking", text);
}
function emitRoleMessage(job, type, text) {
  const normalized = text.trim();
  if (!normalized) return;
  emitInteractionEvent({
    type,
    projectId: job.projectId,
    cardId: job.round.cardId,
    sessionId: job.round.sessionId,
    text: normalized
  });
}
function createAskUserTool(job, cancellation, onUserReply) {
  const interactionDir = job.interactionDir?.trim();
  if (!interactionDir) return void 0;
  mkdirSync2(interactionDir, { recursive: true });
  return {
    description: "\u9700\u8981\u7528\u6237\u786E\u8BA4\u3001\u8865\u5145\u9700\u6C42\u6216\u9009\u62E9\u65B9\u6848\u65F6\u8C03\u7528\u3002\u6709\u4E92\u65A5\u65B9\u6848\u65F6\u4F20\u5165 choices\uFF0C\u770B\u677F\u4F1A\u5F39\u51FA\u9009\u9879\u83DC\u5355\uFF1B\u5DE5\u5177\u4F1A\u6682\u505C\u5F53\u524D\u5361\u7247\uFF0C\u76F4\u5230\u7528\u6237\u56DE\u590D\u3002",
    inputSchema: {
      type: "object",
      properties: {
        question: {
          type: "string",
          description: "\u5411\u7528\u6237\u63D0\u51FA\u7684\u5B8C\u6574\u95EE\u9898\uFF0C\u4F7F\u7528\u7B80\u4F53\u4E2D\u6587\u3002"
        },
        choices: {
          type: "array",
          description: "2 \u5230 4 \u4E2A\u4E92\u65A5\u9009\u9879\u3002\u6709\u660E\u786E\u65B9\u6848\u65F6\u5FC5\u987B\u63D0\u4F9B\uFF0C\u770B\u677F\u4F1A\u5728\u6700\u8FD1\u8FD0\u884C\u754C\u9762\u5F39\u51FA\u9009\u9879\u83DC\u5355\u4F9B\u7528\u6237\u70B9\u9009\uFF1B\u4E0D\u8981\u53EA\u5728\u6B63\u6587\u91CC\u53E3\u5934\u5217\u51FA\u9009\u9879\u3002",
          items: { type: "string" },
          minItems: 2,
          maxItems: 4
        }
      },
      required: ["question"],
      additionalProperties: false
    },
    execute: async (args) => {
      const question = stringArg(args.question);
      if (!question) {
        return { content: [{ type: "text", text: "\u95EE\u9898\u4E0D\u80FD\u4E3A\u7A7A" }], isError: true };
      }
      const explicit = stringListArg(args.choices);
      const choices = explicit.length > 0 ? explicit : inferChoicesFromQuestion(question);
      const requestId = randomUUID();
      const replyPath = join2(interactionDir, `${requestId}.reply.json`);
      emitInteractionEvent({
        type: "question",
        projectId: job.projectId,
        cardId: job.round.cardId,
        sessionId: job.round.sessionId,
        requestId,
        text: question,
        ...choices.length > 0 ? { choices } : {}
      });
      const answer = await waitForReply(replyPath, cancellation);
      if (answer && answer !== "\u7528\u6237\u5DF2\u7EC8\u6B62\u5F53\u524D\u4F1A\u8BDD\u3002") {
        onUserReply?.(answer);
      }
      return answer;
    }
  };
}
async function waitForReply(replyPath, cancellation) {
  while (true) {
    if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
      return "\u7528\u6237\u5DF2\u7EC8\u6B62\u5F53\u524D\u4F1A\u8BDD\u3002";
    }
    if (existsSync3(replyPath)) {
      try {
        const decoded = JSON.parse(readFileSync2(replyPath, "utf8"));
        const text = String(decoded.text ?? "").trim();
        if (text) return text;
      } catch {
      } finally {
        rmSync(replyPath, { force: true });
      }
    }
    await new Promise((resolve2) => setTimeout(resolve2, 250));
  }
}
function stringArg(value) {
  return typeof value === "string" ? value.trim() : "";
}
function stringListArg(value) {
  if (!Array.isArray(value)) return [];
  const choices = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const text = item.trim();
    if (!text || choices.includes(text)) continue;
    choices.push(text);
    if (choices.length >= 4) break;
  }
  return choices.length >= 2 ? choices : [];
}
var choiceLinePattern = /^\s*(?:\d+[\.、\)]|[-*•])\s+(.+)$/;
function inferChoicesFromQuestion(question) {
  const items = [];
  for (const line of question.split(/\r?\n/)) {
    const match = choiceLinePattern.exec(line);
    const text = match?.[1]?.trim() ?? "";
    if (!text || items.includes(text)) continue;
    items.push(text);
    if (items.length >= 4) break;
  }
  return items.length >= 2 ? items : [];
}
function workItems(job) {
  const raw = job.round.cardContext?.workItems;
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      return [];
    }
    const text = String(item.text ?? "").trim();
    return text ? [text] : [];
  });
}

// src/conversation_transcript.ts
var INJECTED_PROMPT_MARKERS = [
  "# Worker \u6CE8\u5165\u7684\u672C\u8F6E\u4E0A\u4E0B\u6587",
  "KANBAN_WORKER_USER_RULES_BEGIN",
  "# Skill \u6B63\u6587",
  "\u770B\u677F MCP \u6536\u5C3E\u5DE5\u5177"
];
function isInjectedWorkerPrompt(text) {
  return INJECTED_PROMPT_MARKERS.some((marker) => text.includes(marker));
}
function buildConversationTranscript(options) {
  const out = [];
  const sessionUser = options.sessionUser.trim();
  if (sessionUser) pushMessage(out, { role: "user", text: sessionUser });
  const live = (options.live ?? []).filter((item) => !isNoiseUser(item, sessionUser));
  const fromTurns = (options.fromTurns ?? []).filter(
    (item) => !isNoiseUser(item, sessionUser)
  );
  const pending = fromTurns.filter((item) => item.role !== "user").map((item) => ({ role: item.role, text: item.text.trim() })).filter((item) => item.text.length > 0);
  const timeline = live.length > 0 ? live : fromTurns;
  for (const message of timeline) {
    if (message.role === "user") {
      pushMessage(out, message);
      continue;
    }
    const liveText = message.text.trim();
    const index = pending.findIndex(
      (item) => item.role === message.role && relatedText(item.text, liveText)
    );
    if (index >= 0) {
      const snapshot = pending.splice(index, 1)[0];
      pushMessage(out, {
        role: message.role,
        text: longerText(snapshot?.text ?? liveText, liveText)
      });
      continue;
    }
    pushMessage(out, message);
  }
  for (const item of pending) {
    pushMessage(out, item);
  }
  if (options.trailingAssistant) {
    pushMessage(out, {
      role: "assistant",
      text: options.trailingAssistant
    });
  }
  return out;
}
function isNoiseUser(message, sessionUser) {
  if (message.role !== "user") return false;
  const text = message.text.trim();
  if (!text) return true;
  if (sessionUser && text === sessionUser) return true;
  return isInjectedWorkerPrompt(text);
}
function relatedText(left, right) {
  return left === right || left.startsWith(right) || right.startsWith(left);
}
function longerText(left, right) {
  return left.length >= right.length ? left : right;
}
function pushMessage(out, message) {
  const text = message.text.trim();
  if (!text) return;
  const last = out[out.length - 1];
  if (last && last.role === message.role && last.text === text) return;
  if (last && last.role === message.role && message.role !== "user") {
    if (text.startsWith(last.text)) {
      last.text = text;
      return;
    }
    if (last.text.startsWith(text)) return;
  }
  if (message.role === "user" && out.some((item) => item.role === "user" && item.text === text)) {
    return;
  }
  out.push({ role: message.role, text });
}

// src/worker_log.ts
import { writeSync as writeSync2 } from "node:fs";
function workerLog(line, source = "worker", level = "info") {
  const prefix = level === "info" ? `[${source}]` : `[${level}] [${source}]`;
  for (const part of line.split(/\r?\n/)) {
    writeSync2(1, `${prefix} ${part}
`);
  }
}
function workerLogRecords(records) {
  for (const record of records) {
    workerLog(record.line, record.source ?? "worker", record.level ?? "info");
  }
}

// src/run_codex.ts
function resolveCodexCommand() {
  const packageRoot = join3(dirname(fileURLToPath(import.meta.url)), "..");
  const bundledCli = join3(
    packageRoot,
    "node_modules",
    "@openai",
    "codex",
    "bin",
    "codex.js"
  );
  if (existsSync4(bundledCli)) {
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
    "--json",
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
  const temp = mkdtempSync2(join3(tmpdir2(), "kanban-codex-"));
  const promptFile = join3(temp, "prompt.txt");
  const lastMessageFile = join3(temp, "last.txt");
  try {
    writeFileSync3(promptFile, job.prompt, "utf8");
    const agentHome = createCodexAgentHome({
      mcpUrl,
      userCodexHome: resolveUserCodexHome(),
      projectMcpTags: job.round.projectMcpTags,
      tempRoot: temp
    });
    workerLog(
      `Codex \u4F7F\u7528\u9694\u79BB CODEX_HOME\uFF0C\u590D\u5236\u7528\u6237 AGENTS.md\uFF08\u8986\u76D6\u5148\u8BFB Architecture\uFF09\u4E0E skills\uFF1B\u5408\u5E76\u7528\u6237 MCP\uFF08${agentHome.mcpServerNames.join(", ") || "\u65E0"}\uFF09\uFF1BkanbanMCP \u5F3A\u5236\u4E3A scoped\uFF08${mcpUrl}\uFF09`
    );
    const args = buildCodexExecArgs({
      cwd: job.cwd,
      lastMessageFile,
      extraConfigArgs: effortToCodexConfigArgs(job),
      model: job.model
    });
    workerLog(`Codex args=${args.join(" ")}`);
    emitSessionStart(job);
    const live = [];
    const sessionUser = sessionStartText(job);
    if (sessionUser) live.push({ role: "user", text: sessionUser });
    const fromTurns = [];
    let endedByTerminal = false;
    const stopAfterTerminal = (reason) => {
      if (endedByTerminal) return;
      endedByTerminal = true;
      workerLog(`\u6536\u5C3E\u5DE5\u5177\u5DF2\u6210\u529F\uFF08${reason}\uFF09\uFF0C\u6B63\u5728\u7ED3\u675F Codex \u4F1A\u8BDD`);
    };
    const emittedAssistant = /* @__PURE__ */ new Set();
    const emittedThinking = /* @__PURE__ */ new Set();
    const emitAssistant = (text) => {
      const normalized = text.trim();
      if (!normalized || emittedAssistant.has(normalized)) return;
      emittedAssistant.add(normalized);
      live.push({ role: "assistant", text: normalized });
      emitAssistantMessage(job, normalized);
    };
    const emitThinking = (text) => {
      const normalized = text.trim();
      if (!normalized || emittedThinking.has(normalized)) return;
      emittedThinking.add(normalized);
      live.push({ role: "thinking", text: normalized });
      emitThinkingMessage(job, normalized);
    };
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
      const terminalPoll = startPollingDispatchTerminal(
        job.round.peekDispatchTerminal,
        (kind) => {
          stopAfterTerminal(`MCP ${kind}`);
          killChild();
        }
      );
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        terminalPoll.stop();
        resolvePromise(130);
        return;
      }
      const logState = createCodexLogState();
      const stdoutLines = createLineBuffer((line) => {
        workerLogRecords(recordsFromCodexJsonLine(line, logState));
        try {
          const parsed = JSON.parse(line);
          const message = extractCodexTranscriptMessage(parsed);
          if (message) fromTurns.push(message);
          if (message?.role === "thinking") emitThinking(message.text);
          emitAssistant(extractCodexAssistantEventText(parsed));
        } catch {
        }
      });
      const stderrLines = createLineBuffer((line) => {
        workerLogRecords(recordsFromCodexStderrLine(line, logState));
      });
      child = spawn2(codex.command, [...codex.prefixArgs, ...args], {
        cwd: job.cwd,
        env: { ...process.env, CODEX_HOME: agentHome.home },
        stdio: ["pipe", "pipe", "pipe"],
        shell: codex.shell
      });
      child.stdout?.on("data", (buf) => {
        stdoutLines.push(buf);
      });
      child.stderr?.on("data", (buf) => {
        stderrLines.push(buf);
      });
      child.on("error", (err) => {
        terminalPoll.stop();
        reject(err);
      });
      if (!child.stdin) {
        terminalPoll.stop();
        reject(new Error("Codex stdin \u4E0D\u53EF\u7528"));
        return;
      }
      child.stdin.write(readFileSync3(promptFile));
      child.stdin.end();
      child.on("close", (exitCode) => {
        stdoutLines.flush();
        stderrLines.flush();
        terminalPoll.stop();
        if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
          resolvePromise(130);
          return;
        }
        resolvePromise(endedByTerminal ? 0 : exitCode ?? 1);
      });
    });
    if (cancellation?.isSkipRequested) {
      workerLog(`Codex exec skipped elapsedMs=${Date.now() - startedAt}`);
      return { ok: false, error: "\u5DF2\u8DF3\u8FC7" };
    }
    if (cancellation?.isCancelled) {
      workerLog(`Codex exec cancelled elapsedMs=${Date.now() - startedAt}`);
      return { ok: false, error: "\u5DF2\u53D6\u6D88" };
    }
    let summary;
    try {
      summary = readFileSync3(lastMessageFile, "utf8").trim();
    } catch {
      summary = void 0;
    }
    workerLog(`Codex exec exitCode=${code} elapsedMs=${Date.now() - startedAt}`);
    if (summary) emitAssistant(summary);
    emitConversationSnapshot(
      job,
      buildConversationTranscript({
        sessionUser,
        live,
        fromTurns,
        trailingAssistant: summary
      })
    );
    if (code === 0) {
      return { ok: true, summary: summary || "Codex \u4F1A\u8BDD\u5B8C\u6210" };
    }
    return {
      ok: false,
      error: `Codex \u9000\u51FA\u7801 ${code}`,
      summary,
      retryable: isRetryableError(summary)
    };
  } catch (error) {
    if (cancellation?.isSkipRequested) {
      return { ok: false, error: "\u5DF2\u8DF3\u8FC7" };
    }
    if (cancellation?.isCancelled) {
      return { ok: false, error: "\u5DF2\u53D6\u6D88" };
    }
    return {
      ok: false,
      error: `Codex \u4F1A\u8BDD\u5F02\u5E38\uFF1A${error instanceof Error ? error.message : String(error)}`,
      retryable: isRetryableError(error)
    };
  } finally {
    try {
      rmSync2(temp, { recursive: true, force: true });
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

// src/cursor_shell_spans.ts
function asRecord5(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}
function pickString3(record, ...keys) {
  if (!record) return "";
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) return value.trim();
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}
function pickNumber(record, ...keys) {
  if (!record) return void 0;
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "number" && Number.isFinite(value)) {
      return Math.trunc(value);
    }
  }
  return void 0;
}
function isShellName(name) {
  return /^(shell|bash|cmd|powershell|pwsh)$/i.test(name);
}
function normalizeDispatchCallId(callId) {
  return (callId ?? "").trim().split(/\s+/).filter((part) => part.length > 0).join("_");
}
function toolPayload2(step) {
  return asRecord5(step.message) ?? asRecord5(step.toolCall) ?? asRecord5(step.call) ?? asRecord5(step.tool) ?? asRecord5(asRecord5(step.message)?.toolCall) ?? asRecord5(asRecord5(step.message)?.call);
}
function extractCommand(message) {
  const nested = asRecord5(message.args) ?? asRecord5(message.arguments) ?? asRecord5(message.input) ?? asRecord5(message.params);
  return pickString3(message, "command", "cmd", "shellCommand") || pickString3(nested, "command", "cmd", "shellCommand");
}
function extractResult(message) {
  const result = asRecord5(message.result) ?? asRecord5(message.output) ?? asRecord5(message.value);
  if (!result) return void 0;
  const value = asRecord5(result.value) ?? result;
  const executionTimeMs = pickNumber(
    value,
    "executionTime",
    "executionTimeMs",
    "execution_time_ms"
  );
  const exitCode = pickNumber(value, "exitCode", "exit_code");
  if (executionTimeMs == null && exitCode == null && asRecord5(message.result) == null) {
    return void 0;
  }
  return { executionTimeMs, exitCode };
}
function extractCallId(record, message) {
  return normalizeDispatchCallId(
    pickString3(message, "call_id", "callId", "id") || pickString3(record, "call_id", "callId")
  );
}
function isReadyToSubmitStep(step) {
  const record = asRecord5(step);
  if (!record) return false;
  const message = toolPayload2(record);
  const nested = asRecord5(message?.args) ?? asRecord5(message?.arguments);
  const toolName = pickString3(message, "toolName", "name") || pickString3(nested, "toolName", "name");
  const type = pickString3(message, "type") || pickString3(record, "type");
  if (toolName === "ready_to_submit") return true;
  return type === "mcp" && pickString3(nested, "toolName") === "ready_to_submit";
}
function isShellSpanEvent(event) {
  if (!event || !("phase" in event)) return false;
  return (event.phase === "start" || event.phase === "end") && normalizeDispatchCallId(event.callId).length > 0;
}
function toShellSpanReportPayload(input) {
  const workerToken = input.workerToken.trim();
  const sessionId = input.sessionId.trim();
  const callId = normalizeDispatchCallId(input.span.callId);
  const phase = input.span.phase;
  const missing = [
    !workerToken ? "workerToken" : "",
    !sessionId ? "sessionId" : "",
    !callId ? "callId" : "",
    phase !== "start" && phase !== "end" ? "phase" : ""
  ].filter(Boolean);
  if (missing.length > 0) {
    throw new Error(`\u4E0A\u62A5 Shell \u65F6\u95F4\u7EBF\u7F3A\u5C11 ${missing.join("\u3001")}`);
  }
  return {
    workerToken,
    sessionId,
    callId,
    command: input.span.command ?? "",
    phase,
    startedAtMs: input.span.startedAtMs,
    ...input.span.endedAtMs != null ? { endedAtMs: input.span.endedAtMs } : {},
    ...input.span.executionTimeMs != null ? { executionTimeMs: input.span.executionTimeMs } : {},
    ...input.span.exitCode != null ? { exitCode: input.span.exitCode } : {}
  };
}
var CursorShellSpanEmitter = class {
  open = /* @__PURE__ */ new Map();
  spans = /* @__PURE__ */ new Map();
  seq = 0;
  lastReadyAtMs;
  observe(step, nowMs) {
    const record = asRecord5(step);
    if (!record) return void 0;
    if (isReadyToSubmitStep(record)) {
      const message2 = toolPayload2(record);
      const hasResult = asRecord5(message2?.result) != null;
      if (!hasResult) this.lastReadyAtMs = nowMs;
      return { kind: "ready", startedAtMs: nowMs };
    }
    const message = toolPayload2(record);
    if (!message) return void 0;
    const name = pickString3(message, "name", "toolName", "functionName", "type") || pickString3(record, "name", "toolName");
    const type = pickString3(record, "type") || pickString3(message, "type");
    if (!isShellName(name) && type !== "shell" && pickString3(message, "type") !== "shell") {
      return void 0;
    }
    const command = extractCommand(message);
    const callId = extractCallId(record, message);
    const result = extractResult(message);
    const isEnd = result != null || type === "toolResult";
    if (isEnd) {
      const open = (callId ? this.open.get(callId) : void 0) ?? [...this.open.values()].find((item) => item.command === command) ?? [...this.open.values()].at(-1);
      if (open) this.open.delete(open.callId);
      const span2 = {
        callId: open?.callId || callId || `end-${this.seq++}`,
        command: command || open?.command || "",
        startedAtMs: open?.startedAtMs ?? nowMs,
        endedAtMs: nowMs,
        executionTimeMs: result?.executionTimeMs,
        exitCode: result?.exitCode
      };
      this.spans.set(span2.callId, span2);
      return { ...span2, phase: "end" };
    }
    const id = callId || `shell-${this.seq++}`;
    const span = {
      callId: id,
      command,
      startedAtMs: nowMs
    };
    this.open.set(id, span);
    this.spans.set(id, span);
    return { ...span, phase: "start" };
  }
  snapshot() {
    return [...this.spans.values()];
  }
  lastReadyStartedAtMs() {
    return this.lastReadyAtMs;
  }
};

// src/run_cursor.ts
import { mkdirSync as mkdirSync3 } from "node:fs";
import { homedir as homedir3 } from "node:os";
import { join as join5 } from "node:path";
import {
  Agent,
  Cursor as Cursor2,
  CursorAgentError,
  JsonlLocalAgentStore
} from "@cursor/sdk";

// src/cursor_mcp_servers.ts
import { existsSync as existsSync5, readFileSync as readFileSync4 } from "node:fs";
import { homedir as homedir2 } from "node:os";
import { join as join4 } from "node:path";
var KANBAN_MCP_SERVER = "kanbanMCP";
function scopedKanbanMcpServer(url) {
  return { type: "http", url: url.trim() };
}
function mergeCursorMcpServers(options) {
  const env = options.env ?? process.env;
  const merged = {
    ...parseMcpServers(options.userJson, env),
    ...parseMcpServers(options.projectJson, env)
  };
  delete merged[KANBAN_MCP_SERVER];
  const allowed = filterRecordByMcpAllowlist(merged, options.projectMcpTags ?? []);
  allowed[KANBAN_MCP_SERVER] = scopedKanbanMcpServer(options.scopedKanbanUrl);
  return allowed;
}
function loadCursorMcpServers(options) {
  const home = options.homeDir ?? homedir2();
  const servers = mergeCursorMcpServers({
    userJson: readOptionalFile(join4(home, ".cursor", "mcp.json")),
    projectJson: readOptionalFile(join4(options.cwd, ".cursor", "mcp.json")),
    scopedKanbanUrl: options.scopedKanbanUrl,
    projectMcpTags: options.projectMcpTags
  });
  return { servers, names: Object.keys(servers) };
}
function parseMcpServers(raw, env) {
  if (raw == null || raw.trim() === "") return {};
  try {
    const decoded = JSON.parse(raw);
    if (!isRecord(decoded)) return {};
    const servers = decoded.mcpServers;
    if (!isRecord(servers)) return {};
    const result = {};
    for (const [name, value] of Object.entries(servers)) {
      if (name === KANBAN_MCP_SERVER) continue;
      const converted = toSdkServer(value, env);
      if (converted != null) result[name] = converted;
    }
    return result;
  } catch {
    return {};
  }
}
function toSdkServer(raw, env) {
  if (!isRecord(raw)) return null;
  if (typeof raw.url === "string" && raw.url.trim() !== "") {
    const type = raw.type === "sse" ? "sse" : "http";
    const server = {
      type,
      url: expandEnvTemplates(raw.url.trim(), env)
    };
    if (isRecord(raw.headers)) {
      server.headers = expandStringRecord(raw.headers, env);
    }
    return server;
  }
  if (typeof raw.command === "string" && raw.command.trim() !== "") {
    const server = {
      command: expandEnvTemplates(raw.command.trim(), env)
    };
    if (Array.isArray(raw.args)) {
      server.args = raw.args.filter((item) => typeof item === "string").map((item) => expandEnvTemplates(item, env));
    }
    if (isRecord(raw.env)) {
      server.env = expandStringRecord(raw.env, env);
    }
    return server;
  }
  return null;
}
function expandStringRecord(record, env) {
  const result = {};
  for (const [key, value] of Object.entries(record)) {
    if (typeof value === "string") {
      result[key] = expandEnvTemplates(value, env);
    }
  }
  return result;
}
function expandEnvTemplates(value, env = process.env) {
  return value.replace(/\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}/g, (original, name) => {
    const resolved = env[name];
    return resolved == null || resolved === "" ? original : resolved;
  });
}
function readOptionalFile(path) {
  if (!existsSync5(path)) return null;
  try {
    return readFileSync4(path, "utf8");
  } catch {
    return null;
  }
}
function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

// src/cursor_disallowed_tools.ts
var CURSOR_WORKER_DISALLOWED_TOOLS = [
  "GetMcpTools",
  "askQuestion"
];
var CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK = [];
function fallbackDisallowedTools(err) {
  const message = err instanceof Error ? err.message : String(err);
  if (!/GetMcpTools/i.test(message)) return null;
  return CURSOR_WORKER_DISALLOWED_TOOLS_FALLBACK;
}

// src/cursor_sdk_scan_log.ts
function parseCursorSdkScanLog(line) {
  const text = line.trim();
  if (text.includes("AgentSkillsCursorRulesService load completed")) {
    return {
      kind: "skills",
      ruleCount: readMetaCount(text, "ruleCount"),
      skillCount: readMetaCount(text, "skillCount")
    };
  }
  if (text.includes("LocalCursorRulesService load completed")) {
    return {
      kind: "rules",
      ruleCount: readMetaCount(text, "ruleCount")
    };
  }
  return void 0;
}
function formatCursorSdkScanNote(scan) {
  if (scan.kind === "skills") {
    const count2 = formatCount(scan.skillCount ?? scan.ruleCount);
    return `SDK \u626B\u63CF Skill\uFF1A${count2}\uFF08\u542B\u672C\u673A ~/.cursor/skills-cursor \u5185\u7F6E\uFF09\uFF0C\u8FD9\u662F\u53EF\u4F9B Cursor \u6309\u89E6\u53D1\u6761\u4EF6\u9009\u62E9\u7684 Skill\uFF1B\u4E0D\u4F1A\u5C06\u5168\u90E8 Skill \u6B63\u6587\u540C\u65F6\u6CE8\u5165`;
  }
  const count = formatCount(scan.ruleCount);
  return `SDK \u626B\u63CF Rule\uFF1A${count}\uFF0C\u8FD9\u662F\u8FC7\u6EE4\u524D\u7684\u626B\u63CF\u6570\uFF1B\u7528\u6237 Rule \u5DF2\u7531 Worker \u5199\u5165 prompt\uFF1BSDK \u540C\u65F6\u52A0\u8F7D\u9879\u76EE\u4E0E\u7528\u6237\u8BBE\u7F6E\u5C42`;
}
function createCursorSdkScanLogBuffer(onNote) {
  let pending = "";
  const emit = (line) => {
    const scan = parseCursorSdkScanLog(line);
    if (scan) onNote(formatCursorSdkScanNote(scan));
  };
  return {
    push(chunk) {
      pending += chunk.replaceAll("\r\n", "\n").replaceAll("\r", "\n");
      let index = pending.indexOf("\n");
      while (index >= 0) {
        emit(pending.slice(0, index));
        pending = pending.slice(index + 1);
        index = pending.indexOf("\n");
      }
    },
    flush() {
      if (!pending) return;
      emit(pending);
      pending = "";
    }
  };
}
function installCursorSdkScanLogTap(log = (line) => workerLog(line)) {
  const buffer = createCursorSdkScanLogBuffer(log);
  const restoreStdout = wrapWriteStream(process.stdout, buffer);
  const restoreStderr = wrapWriteStream(process.stderr, buffer);
  return () => {
    buffer.flush();
    restoreStdout();
    restoreStderr();
  };
}
function readMetaCount(text, key) {
  const match = new RegExp(`${key}\\s*[:=]\\s*(\\d+)`).exec(text);
  if (!match) return void 0;
  return Number.parseInt(match[1] ?? "", 10);
}
function formatCount(value) {
  return value == null || !Number.isFinite(value) ? "\u82E5\u5E72" : `${value} \u4E2A`;
}
function wrapWriteStream(stream, buffer) {
  const original = stream.write.bind(stream);
  const wrapped = ((chunk, encoding, callback) => {
    const encodingName = typeof encoding === "string" ? encoding : "utf8";
    const text = Buffer.isBuffer(chunk) ? chunk.toString(encodingName) : typeof chunk === "string" ? chunk : String(chunk ?? "");
    buffer.push(text);
    if (typeof encoding === "function") {
      return original(chunk, encoding);
    }
    return original(chunk, encoding, callback);
  });
  stream.write = wrapped;
  return () => {
    stream.write = original;
  };
}

// src/cursor_thinking_stream.ts
function defaultSchedule(fn, ms) {
  const timer = setTimeout(fn, ms);
  timer.unref?.();
  return { cancel: () => clearTimeout(timer) };
}
var CursorThinkingStream = class {
  write;
  intervalMs;
  schedule;
  pending = "";
  assembled = "";
  startedBlock = false;
  streamed = false;
  blockComplete = false;
  scheduled;
  constructor(options = {}) {
    this.write = options.write ?? ((line, source) => workerLog(line, source ?? "ai"));
    this.intervalMs = options.intervalMs ?? 800;
    this.schedule = options.schedule ?? defaultSchedule;
  }
  notePromptSent() {
    this.write(
      "\u5DF2\u53D1\u9001\u4EFB\u52A1\uFF0C\u6B63\u5728\u7B49\u5F85\u6A21\u578B\u601D\u8003\u6D41\u3002\u5B8C\u6574\u601D\u8003\u6B65\u9AA4\u8981\u7B49\u8FD9\u6BB5\u601D\u8003\u7ED3\u675F\u540E\u624D\u5230\u8FBE\uFF0C\u4E2D\u95F4\u7A7A\u767D\u4E0D\u4EE3\u8868\u7A7A\u95F2\u3002",
      "worker"
    );
  }
  handleDelta(update) {
    if (!update || typeof update !== "object") return;
    const record = update;
    const type = typeof record.type === "string" ? record.type : "";
    const nested = record.message && typeof record.message === "object" ? record.message : void 0;
    const deltaText = [record.text, record.delta, nested?.text].find(
      (value) => typeof value === "string" && value.length > 0
    );
    if (type === "thinking" && deltaText) {
      this.replaceAssembled(deltaText);
      return;
    }
    if (type === "thinking-delta" && deltaText) {
      this.appendDelta(deltaText);
      return;
    }
    if (type === "thinking-completed") {
      this.flush(true);
      this.blockComplete = true;
      const ms = record.thinkingDurationMs;
      if (typeof ms === "number" && Number.isFinite(ms) && ms >= 0) {
        this.write(`\u601D\u8003\u5B8C\u6210\uFF08${Math.round(ms / 1e3)} \u79D2\uFF09`, "ai");
      }
    }
  }
  /** 当前已组装的思考正文，供写入同步对话；不消费日志去重状态。 */
  assembledText() {
    return `${this.assembled}${this.pending}`.trim();
  }
  /** 若思考已通过增量打出，则跳过 onStep 的整段重复 dump。 */
  consumeStreamedThinking() {
    if (!this.streamed) return false;
    this.streamed = false;
    this.startedBlock = false;
    return true;
  }
  dispose() {
    this.scheduled?.cancel();
    this.scheduled = void 0;
    this.flush(true);
  }
  replaceAssembled(text) {
    if (this.blockComplete) {
      this.assembled = "";
      this.pending = "";
      this.startedBlock = false;
      this.streamed = false;
      this.blockComplete = false;
    }
    this.assembled = text;
    this.pending = "";
  }
  appendDelta(text) {
    if (this.blockComplete) {
      this.assembled = "";
      this.pending = "";
      this.startedBlock = false;
      this.streamed = false;
      this.blockComplete = false;
    }
    const addition = this.deltaAddition(text);
    if (!addition) return;
    this.pending += addition;
    if (this.pending.includes("\n")) {
      this.flush(false);
      return;
    }
    this.ensureScheduled();
  }
  deltaAddition(text) {
    if (this.assembled && text.startsWith(this.assembled) && text.length >= this.assembled.length) {
      const extra = text.slice(this.assembled.length);
      this.assembled = text;
      return extra;
    }
    this.assembled += text;
    return text;
  }
  ensureScheduled() {
    if (this.scheduled || this.pending.length === 0) return;
    this.scheduled = this.schedule(() => {
      this.scheduled = void 0;
      this.flush(false);
    }, this.intervalMs);
  }
  flush(force) {
    if (!this.pending) return;
    let emit = this.pending;
    let keep = "";
    if (!force) {
      const lastNl = this.pending.lastIndexOf("\n");
      if (lastNl < 0) {
        emit = this.pending;
        keep = "";
      } else {
        emit = this.pending.slice(0, lastNl);
        keep = this.pending.slice(lastNl + 1);
      }
    }
    this.pending = keep;
    const lines = emit.split(/\r?\n/).map((line) => line.replace(/\s+$/, "")).filter((line) => line.length > 0);
    if (lines.length === 0) return;
    this.streamed = true;
    for (const line of lines) {
      if (!this.startedBlock) {
        this.write(`\u601D\u8003\uFF1A${line}`, "ai");
        this.startedBlock = true;
      } else {
        this.write(`  \u2502 ${line}`, "ai");
      }
    }
  }
};

// src/run_diagnostics.ts
var AgentRunDiagnostics = class {
  steps = 0;
  toolCalls = 0;
  repeatedToolCalls = 0;
  signatures = /* @__PURE__ */ new Map();
  reads = /* @__PURE__ */ new Map();
  recordStep(input) {
    this.steps += 1;
    if (input.type !== "toolCall") return;
    this.toolCalls += 1;
    const name = input.toolName?.trim() || "tool";
    const detail = input.detail?.trim() || "";
    const signature = `${name.toLowerCase()}\0${detail}`;
    const seen = this.signatures.get(signature) ?? 0;
    if (seen > 0) this.repeatedToolCalls += 1;
    this.signatures.set(signature, seen + 1);
    if (name.toLowerCase() === "read") {
      const path = readPath(detail);
      if (path) this.reads.set(path, (this.reads.get(path) ?? 0) + 1);
    }
  }
  snapshot() {
    const repeatedReads = [...this.reads.values()].reduce(
      (sum, count) => sum + Math.max(0, count - 1),
      0
    );
    const topReads = [...this.reads.entries()].filter(([, count]) => count > 1).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 3).map(([path, count]) => `${path}\xD7${count}`);
    return {
      steps: this.steps,
      toolCalls: this.toolCalls,
      repeatedToolCalls: this.repeatedToolCalls,
      repeatedReads,
      topReads
    };
  }
};
function formatAgentRunDiagnostics(metrics) {
  return `\u4F1A\u8BDD\u8BCA\u65AD\uFF1Asteps=${metrics.steps} tools=${metrics.toolCalls} repeatedToolCalls=${metrics.repeatedToolCalls} repeatedReads=${metrics.repeatedReads}` + (metrics.topReads.length > 0 ? ` topReads=${metrics.topReads.join(",")}` : "");
}
function readPath(detail) {
  try {
    const parsed = JSON.parse(detail);
    const value = parsed.path ?? parsed.filePath ?? parsed.file_path;
    if (typeof value === "string" && value.trim()) {
      return value.trim().replaceAll("\\", "/").toLowerCase();
    }
  } catch {
  }
  const raw = detail.trim();
  return raw && !raw.startsWith("{") ? raw.replaceAll("\\", "/").toLowerCase() : void 0;
}

// src/verification_ready_gate.ts
var VERIFICATION_MARKERS = [
  "flutter test",
  "flutter analyze",
  "dart test",
  "dart analyze",
  "dotnet test",
  "node --test",
  "node.exe --test",
  "npm test",
  "npx test",
  "pnpm test",
  "yarn test",
  "pytest",
  "cargo test",
  "go test",
  "mvn test",
  "gradle test",
  "gradlew test",
  "ctest",
  "vitest",
  "jest"
];
function isVerificationCommand(command) {
  const text = command.toLowerCase();
  return VERIFICATION_MARKERS.some((marker) => text.includes(marker));
}
var IMPLAUSIBLE_TEST_DURATION_MS = 2e3;
function isSlowTestCommand(command) {
  const text = command.toLowerCase();
  return text.includes("flutter test") || text.includes("dart test");
}
function shellObservedDurationMs(span) {
  const exec = span.executionTimeMs ?? 0;
  if (exec > 0) return exec;
  if (span.endedAtMs == null) return -1;
  return span.endedAtMs - span.startedAtMs;
}
function shellEffectiveEndMs(span) {
  const exec = span.executionTimeMs ?? 0;
  if (exec > 0) return span.startedAtMs + exec;
  if (span.endedAtMs == null) return Number.MAX_SAFE_INTEGER;
  return span.endedAtMs;
}
function isImplausiblyShortSuccessfulTest(span) {
  if (!isSlowTestCommand(span.command)) return false;
  if (span.exitCode != null && span.exitCode !== 0) return false;
  const duration = shellObservedDurationMs(span);
  if (duration < 0) return false;
  return duration < IMPLAUSIBLE_TEST_DURATION_MS;
}
function commandLooksLikeCdAndChain(command) {
  return /\bcd\b[^&\n]*&&/i.test(command);
}
function isUneexecutedCdAndVerification(span) {
  const code = span.exitCode;
  if (code == null || code === 0) return false;
  if (!commandLooksLikeCdAndChain(span.command)) return false;
  if (!isVerificationCommand(span.command)) return false;
  const exec = span.executionTimeMs;
  if (exec != null && exec >= 3e3) return false;
  return true;
}
function readyBlockedByShells(spans, nowMs) {
  const verification = spans.filter((span) => isVerificationCommand(span.command));
  if (verification.length === 0) return void 0;
  const authoritative = verification.filter(
    (span) => !isUneexecutedCdAndVerification(span)
  );
  const pool = authoritative.length > 0 ? authoritative : verification;
  let lastVerification;
  let lastEndMs = -1;
  for (const span of pool) {
    const endMs = shellEffectiveEndMs(span);
    if (lastVerification == null || endMs >= lastEndMs) {
      lastVerification = span;
      lastEndMs = endMs;
    }
  }
  if (!lastVerification) return void 0;
  if (nowMs < lastEndMs) {
    return `\u9A8C\u8BC1\u547D\u4EE4\u4ECD\u5728\u6267\u884C\uFF1A${clip2(lastVerification.command)}\u3002\u8BF7\u7B49\u5F85\u6D4B\u8BD5\u5B8C\u6210\u540E\u518D\u8C03\u7528 ready_to_submit\uFF0C\u4E0D\u8981\u4E0E Shell \u5E76\u884C\u3002`;
  }
  const code = lastVerification.exitCode;
  if (code != null && code !== 0) {
    const hint = commandLooksLikeCdAndChain(lastVerification.command) ? "PowerShell 5.1 \u4E0D\u652F\u6301 &&\uFF1B\u8BF7\u7528 working_directory\uFF0C\u4E0D\u8981\u5199 cd ... &&\u3002" : "\u8BF7\u4FEE\u590D\u540E\u91CD\u8DD1\u6D4B\u8BD5\uFF0C\u518D\u8C03\u7528 ready_to_submit\u3002";
    return `\u9A8C\u8BC1\u547D\u4EE4\u5931\u8D25\uFF08exitCode=${code}\uFF09\uFF1A${clip2(lastVerification.command)}\u3002${hint}`;
  }
  if (isImplausiblyShortSuccessfulTest(lastVerification)) {
    const duration = shellObservedDurationMs(lastVerification);
    return `\u9A8C\u8BC1\u547D\u4EE4\u8017\u65F6\u8FC7\u77ED\uFF08${duration}ms\uFF09\uFF0C\u4E0D\u50CF\u771F\u6B63\u8DD1\u5B8C\u6D4B\u8BD5\uFF1A${clip2(lastVerification.command)}\u3002\u8BF7\u786E\u8BA4 working_directory \u4E0E\u76F8\u5BF9\u8DEF\u5F84\u4E00\u81F4\uFF0C\u5E76\u7B49\u5230 flutter test / dart test \u5B9E\u9645\u7ED3\u675F\u540E\u518D ready_to_submit\u3002`;
  }
  return void 0;
}
function clip2(command) {
  const text = command.trim();
  return text.length <= 180 ? text : `${text.slice(0, 179)}\u2026`;
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
function expandMultiline2(prefix, body) {
  const lines = body.replace(/\s+$/, "").split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) return [`${prefix}\uFF08\u7A7A\uFF09`];
  const result = [`${prefix}${lines[0]}`];
  for (let i = 1; i < lines.length; i++) {
    result.push(`  \u2502 ${lines[i]}`);
  }
  return result;
}
function asRecord6(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}
function pickString4(message, ...keys) {
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
    return asRecord6(JSON.parse(trimmed));
  } catch {
    return void 0;
  }
}
function usefulJson2(value, max = 4e3) {
  if (value === void 0 || value === null) return "";
  if (typeof value === "string") return value.trim();
  const text = formatJson(value, max);
  if (!text || text === "{}" || text === "[]" || text === "null") return "";
  return text;
}
function toolPayload3(step) {
  return asRecord6(step.message) ?? asRecord6(step.toolCall) ?? asRecord6(step.call) ?? asRecord6(step.tool) ?? asRecord6(asRecord6(step.message)?.toolCall) ?? asRecord6(asRecord6(step.message)?.call);
}
function extractToolDetail(payload) {
  if (!payload) return "";
  const nested = asRecord6(payload.args) ?? asRecord6(payload.arguments) ?? asRecord6(payload.input) ?? asRecord6(payload.params) ?? asRecord6(asRecord6(payload.function)?.arguments) ?? parseJsonRecord(payload.args) ?? parseJsonRecord(payload.arguments) ?? parseJsonRecord(asRecord6(payload.function)?.arguments);
  const command = pickString4(
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
    const nestedCommand = pickString4(
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
      const rest = usefulJson2(extra, 2e3);
      return rest ? `${nestedCommand}  ${rest}` : nestedCommand;
    }
    return usefulJson2(nested);
  }
  const rawArgs = payload.args ?? payload.arguments ?? payload.input ?? payload.params;
  if (typeof rawArgs === "string" && rawArgs.trim()) return rawArgs.trim();
  return "";
}
function isShellTool(name) {
  return /^(shell|bash|cmd|powershell|pwsh)$/i.test(name);
}
function describeStep(step) {
  const record = asRecord6(step) ?? {};
  const type = String(record.type ?? "unknown");
  const message = toolPayload3(record);
  switch (type) {
    case "assistantMessage":
      return {
        lines: expandMultiline2("\u52A9\u624B\uFF1A", extractCursorAssistantStepText(record)),
        source: "ai"
      };
    case "thinkingMessage": {
      const text = pickString4(message, "text", "thinking", "content");
      return {
        lines: text ? expandMultiline2("\u601D\u8003\uFF1A", text) : [],
        source: "ai"
      };
    }
    case "toolCall": {
      const toolName = pickString4(message, "name", "toolName", "functionName", "type") || pickString4(record, "name", "toolName") || "tool";
      const detail = extractToolDetail(message);
      if (!detail) {
        return {
          lines: [`\u5DE5\u5177\uFF1A${toolName}`],
          source: isShellTool(toolName) ? "shell" : "mcp",
          toolName
        };
      }
      if (isShellTool(toolName)) {
        return {
          lines: expandMultiline2("\u547D\u4EE4\uFF1A", detail),
          source: "shell",
          toolName,
          detail
        };
      }
      return {
        lines: expandMultiline2(`\u5DE5\u5177\uFF1A${toolName} `, detail),
        source: "mcp",
        toolName,
        detail
      };
    }
    case "toolResult": {
      const toolName = pickString4(message, "name", "toolName", "type") || "tool";
      const result = message?.result ?? message?.output ?? message?.content ?? message?.text;
      if (result === void 0) {
        return { lines: [], source: "mcp" };
      }
      const body = typeof result === "string" ? result : formatJson(result);
      if (!String(body).trim()) return { lines: [], source: "mcp" };
      return {
        lines: expandMultiline2(`\u5DE5\u5177\u7ED3\u679C\uFF1A${toolName} `, body),
        source: "mcp"
      };
    }
    case "shellConversationTurn":
    case "shell": {
      const command = extractToolDetail(message) || pickString4(message, "command", "text");
      if (!command) return { lines: [], source: "shell" };
      return {
        lines: expandMultiline2("\u547D\u4EE4\uFF1A", command),
        source: "shell"
      };
    }
    default: {
      const detail = message ? usefulJson2(message, 800) : "";
      if (!detail) return { lines: [], source: "worker" };
      return {
        lines: [`\u6B65\u9AA4\uFF1A${type} ${detail}`],
        source: "worker"
      };
    }
  }
}
function catalogParameterValues(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    if (typeof item === "string" && item.trim()) return [item.trim()];
    if (item && typeof item === "object" && "value" in item) {
      const text = String(item.value ?? "").trim();
      return text ? [text] : [];
    }
    return [];
  });
}
async function attachLiveCursorModelCatalog(job, apiKey) {
  try {
    const models = await withRetry(
      "\u62C9\u53D6 Cursor \u6A21\u578B\u76EE\u5F55",
      () => Cursor2.models.list({ apiKey }),
      { maxAttempts: 2, baseDelayMs: 400 }
    );
    const mapped = models.map((item) => ({
      id: item.id,
      parameters: (item.parameters ?? []).map((parameter) => ({
        id: parameter.id,
        values: catalogParameterValues(parameter.values)
      }))
    }));
    logLine(`\u5DF2\u7528 Cursor.models.list \u6838\u5BF9\u53C2\u6570\uFF08${mapped.length} \u4E2A\u6A21\u578B\uFF09`);
    return withCursorSdkCatalog(job, mapped);
  } catch (err) {
    logLine(
      `\u62C9\u53D6 Cursor \u6A21\u578B\u76EE\u5F55\u5931\u8D25\uFF0C\u6539\u7528\u5DE5\u4F5C\u53F0\u7F13\u5B58\uFF1A${err instanceof Error ? err.message : String(err)}`
    );
    return job;
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
  const jobWithCatalog = await attachLiveCursorModelCatalog(job, apiKey);
  const selected = selectCursorSdkModelParams(jobWithCatalog);
  let params = selected.params;
  logLine(`Cursor \u6A21\u578B=${modelId} params=${JSON.stringify(params ?? [])}`);
  if (selected.dropped.length > 0) {
    logLine(
      `\u672A\u4F20\u7ED9 Cursor SDK\uFF1A${selected.dropped.join(", ")}\uFF08\u5F53\u524D\u6A21\u578B\u76EE\u5F55\u4E0D\u652F\u6301\uFF0C\u6216\u5C5E\u4E8E\u770B\u677F\u81EA\u9020\u53C2\u6570\uFF09\u3002` + (selected.dropped.includes("fast") ? "\u5F53\u524D\u6A21\u578B\u6CA1\u6709 fast\uFF0C\u5F00\u542F\u5FEB\u901F\u6A21\u5F0F\u4E0D\u4F1A\u751F\u6548\u3002" : "")
    );
  }
  const agentMcpUrl = job.round.agentEndpointUrl.trim();
  if (!agentMcpUrl) {
    return { ok: false, error: "\u672C\u8F6E claim \u7F3A\u5C11 scoped MCP \u7AEF\u70B9" };
  }
  try {
    process.chdir(job.cwd);
    const startedAt = Date.now();
    let stepCount = 0;
    let toolCallCount = 0;
    const diagnostics = new AgentRunDiagnostics();
    const shellSpans = new CursorShellSpanEmitter();
    const live = [];
    const askUserTool = createAskUserTool(job, cancellation, (text) => {
      live.push({ role: "user", text });
    });
    const storeDir = join5(homedir3(), ".cursor", "kanban-agent-jsonl-store");
    mkdirSync3(storeDir, { recursive: true });
    const mcp = loadCursorMcpServers({
      cwd: job.cwd,
      scopedKanbanUrl: agentMcpUrl,
      projectMcpTags: job.round.projectMcpTags
    });
    const localOptions = {
      cwd: job.cwd,
      // 用户 Rule 已由 Worker 完整注入；同时启用 user 让 Cursor 按 Skill
      // frontmatter 的 description / 触发条件自行选择用户 Skill，而非把所有
      // Skill 正文拼进本卡 prompt。MCP 仍由 mcpServers 显式控制。
      settingSources: ["project", "user"],
      store: new JsonlLocalAgentStore(storeDir),
      ...askUserTool ? { customTools: { ask_user: askUserTool } } : {},
      // 无头 Worker 无人点批准；Auto-review 会拦 ready_to_submit 导致整卡失败。
      autoReview: false,
      sandboxOptions: { enabled: job.enableSandbox === true }
    };
    const createOptions = (modelParams) => ({
      apiKey,
      model: {
        id: modelId,
        ...modelParams && modelParams.length > 0 ? { params: modelParams } : {}
      },
      mcpServers: mcp.servers,
      local: localOptions
    });
    let disallowedTools = CURSOR_WORKER_DISALLOWED_TOOLS;
    let agent;
    const stopScanLog = installCursorSdkScanLogTap();
    let thinkingStream;
    try {
      try {
        agent = await Agent.create({
          ...createOptions(params),
          disallowedTools
        });
      } catch (err) {
        const fallback = fallbackDisallowedTools(err);
        const stripped = nextCursorSdkParamsAfterCreateError(params, err);
        if (fallback == null && !stripped.changed) throw err;
        if (fallback != null) disallowedTools = fallback;
        if (stripped.changed) {
          params = stripped.params;
          logLine(
            `Cursor \u62D2\u7EDD\u53C2\u6570 ${stripped.dropped.join(", ")}\uFF0C\u5DF2\u53BB\u6389\u540E\u91CD\u8BD5\u521B\u5EFA\u4F1A\u8BDD\u3002`
          );
        }
        agent = await Agent.create({
          ...createOptions(params),
          disallowedTools
        });
      }
      logLine(
        `\u672C\u5730\u8FD0\u884C\uFF1AJSONL \u5B58\u50A8=${storeDir}\uFF1B\u6C99\u7BB1${job.enableSandbox === true ? "\u5F00\u542F" : "\u5173\u95ED"}\uFF1B\u5408\u5E76 MCP\uFF08${mcp.names.join(", ") || "\u65E0"}\uFF09\uFF1BkanbanMCP \u5F3A\u5236\u4E3A scoped\uFF08${agentMcpUrl}\uFF09\uFF1B\u7981\u7528\u5DE5\u5177=${disallowedTools.join(",") || "\u65E0"}\uFF1BsettingSources=project,user\uFF08\u7528\u6237\u4E0E\u9879\u76EE Skill \u7531 Cursor \u6309\u5404\u81EA\u89E6\u53D1\u6761\u4EF6\u9009\u62E9\uFF1B\u7528\u6237 Rule \u5DF2\u7531 Worker \u6CE8\u5165\uFF1BMCP \u4EC5\u4F7F\u7528\u672C\u8F6E\u663E\u5F0F\u5408\u5E76\u7684\u670D\u52A1\u5668\uFF09`
      );
      logLine("\u672C\u5730\u4F1A\u8BDD\u5DF2\u521B\u5EFA\uFF0C\u5F00\u59CB\u6267\u884C\u2026");
      thinkingStream = new CursorThinkingStream();
      thinkingStream.notePromptSent();
      emitSessionStart(job);
      const sessionUser = sessionStartText(job);
      if (sessionUser) live.push({ role: "user", text: sessionUser });
      const emittedAssistant = /* @__PURE__ */ new Set();
      const emittedThinking = /* @__PURE__ */ new Set();
      const emitAssistant = (text) => {
        const normalized = text.trim();
        if (!normalized || emittedAssistant.has(normalized)) return;
        emittedAssistant.add(normalized);
        live.push({ role: "assistant", text: normalized });
        emitAssistantMessage(job, normalized);
      };
      const emitThinking = (text) => {
        const normalized = text.trim();
        if (!normalized || emittedThinking.has(normalized)) return;
        emittedThinking.add(normalized);
        live.push({ role: "thinking", text: normalized });
        emitThinkingMessage(job, normalized);
      };
      const flushSnapshot = (turns2 = [], trailing) => {
        emitConversationSnapshot(
          job,
          buildConversationTranscript({
            sessionUser,
            live,
            fromTurns: extractConversationMessages(turns2),
            trailingAssistant: trailing
          })
        );
      };
      let endedByTerminal = false;
      let runCancel;
      const stopAfterTerminal = (reason) => {
        if (endedByTerminal) return;
        endedByTerminal = true;
        logLine(`\u6536\u5C3E\u5DE5\u5177\u5DF2\u6210\u529F\uFF08${reason}\uFF09\uFF0C\u6B63\u5728\u7ED3\u675F Cursor \u4F1A\u8BDD`);
        void runCancel?.().catch(() => void 0);
      };
      const run = await agent.send({
        text: askUserTool ? `${job.prompt}

## \u770B\u677F\u4EA4\u4E92
\u9700\u8981\u7528\u6237\u786E\u8BA4\u3001\u8865\u5145\u9700\u6C42\u6216\u9009\u62E9\u65B9\u6848\u65F6\u5FC5\u987B\u8C03\u7528 ask_user\uFF1B\u4E0D\u8981\u8C03\u7528 askQuestion\uFF0C\u4E5F\u4E0D\u8981\u53EA\u5728\u52A9\u624B\u6B63\u6587\u91CC\u53E3\u5934\u5217\u51FA\u9009\u9879\u3002\u6709 2\u20134 \u4E2A\u4E92\u65A5\u65B9\u6848\u65F6\u5FC5\u987B\u4F20\u5165 choices\uFF0C\u770B\u677F\u4F1A\u5728\u6700\u8FD1\u8FD0\u884C\u754C\u9762\u5F39\u51FA\u9009\u9879\u83DC\u5355\u5E76\u7B49\u5F85\u56DE\u590D\u3002` : job.prompt,
        images: job.round.images
      }, {
        mcpServers: mcp.servers,
        onDelta: ({ update }) => {
          thinkingStream?.handleDelta(update);
          const type = update && typeof update === "object" && "type" in update ? String(update.type ?? "") : "";
          if (type === "thinking-completed" || type === "thinking") {
            emitThinking(thinkingStream?.assembledText() ?? "");
          }
        },
        onStep: async ({ step }) => {
          try {
            stepCount += 1;
            if (step.type === "toolCall") toolCallCount += 1;
            const described = describeStep(
              step
            );
            diagnostics.recordStep({
              type: String(step.type),
              toolName: described.toolName,
              detail: described.detail
            });
            const skipThinkingDump = step.type === "thinkingMessage" && thinkingStream?.consumeStreamedThinking() === true;
            if (!skipThinkingDump && described.lines.length > 0) {
              logLines(described.lines, described.source);
            }
            if (step.type === "thinkingMessage") {
              emitThinking(
                extractCursorThinkingStepText(step) || thinkingStream?.assembledText() || ""
              );
            }
            if (step.type === "assistantMessage") {
              emitAssistant(extractCursorAssistantStepText(step));
            }
          } catch {
            logLine("\u6536\u5230\u4E00\u6B65\u8FDB\u5EA6");
          }
          try {
            const event = shellSpans.observe(step, Date.now());
            if (isShellSpanEvent(event)) {
              await job.round.reportShellSpan?.(event);
            }
            if (isSuccessfulDispatchTerminalStep(step)) {
              stopAfterTerminal("\u5DE5\u5177\u7ED3\u679C");
            }
          } catch (err) {
            logLine(
              `\u4E0A\u62A5 Shell \u65F6\u95F4\u7EBF\u5931\u8D25\uFF1A${err instanceof Error ? err.message : String(err)}`
            );
          }
        }
      });
      cancellation?.onCancel(() => {
        void run.cancel().catch(() => void 0);
      });
      runCancel = () => run.cancel();
      if (endedByTerminal) {
        await run.cancel().catch(() => void 0);
      }
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        await run.cancel().catch(() => void 0);
      }
      const terminalPoll = startPollingDispatchTerminal(
        job.round.peekDispatchTerminal,
        (kind) => stopAfterTerminal(`MCP ${kind}`)
      );
      let result;
      try {
        result = await run.wait();
      } finally {
        terminalPoll.stop();
      }
      let turns = [];
      try {
        turns = await run.conversation();
        for (const message of extractConversationMessages(turns)) {
          if (message.role === "thinking") emitThinking(message.text);
          if (message.role === "assistant") emitAssistant(message.text);
        }
      } catch {
      }
      if (typeof result.result === "string") {
        emitAssistant(result.result);
      }
      flushSnapshot(
        turns,
        typeof result.result === "string" ? result.result : void 0
      );
      const metrics = diagnostics.snapshot();
      logLine(formatAgentRunDiagnostics(metrics));
      logLine(
        `Cursor run id=${result.id} status=${result.status} steps=${stepCount} tools=${toolCallCount} elapsedMs=${Date.now() - startedAt}`
      );
      if (result.usage && toDashboardTokenUsage(result.usage).totalTokens > 0) {
        logLine(formatSessionTokenLog(result.usage, metrics));
      }
      if (cancellation?.isSkipRequested) {
        logLine("Cursor \u4F1A\u8BDD\u5DF2\u7531\u7528\u6237\u8DF3\u8FC7", "worker");
        return { ok: false, error: "\u5DF2\u8DF3\u8FC7" };
      }
      if (cancellation?.isCancelled && !endedByTerminal) {
        logLine("Cursor \u4F1A\u8BDD\u5DF2\u7531\u7528\u6237\u505C\u6B62", "worker");
        return { ok: false, error: "\u5DF2\u53D6\u6D88" };
      }
      if (endedByTerminal) {
        const readyAt2 = shellSpans.lastReadyStartedAtMs();
        if (readyAt2 != null) {
          const blocked = readyBlockedByShells(shellSpans.snapshot(), readyAt2);
          if (blocked) {
            logLine(blocked);
            return { ok: false, error: blocked };
          }
        }
        return {
          ok: true,
          summary: typeof result.result === "string" ? result.result : "\u6536\u5C3E\u5DE5\u5177\u5DF2\u6210\u529F\uFF0C\u5DF2\u7ED3\u675F\u4F1A\u8BDD"
        };
      }
      if (result.status === "cancelled") {
        logLine("Cursor \u4F1A\u8BDD\u5DF2\u7531\u7528\u6237\u505C\u6B62", "worker");
        return { ok: false, error: "\u5DF2\u53D6\u6D88" };
      }
      if (result.status === "error") {
        return {
          ok: false,
          error: `Cursor run \u5931\u8D25\uFF1A${result.error?.message ?? result.id}`,
          summary: typeof result.result === "string" ? result.result : void 0,
          retryable: isRetryableError(result.error)
        };
      }
      const readyAt = shellSpans.lastReadyStartedAtMs();
      if (readyAt != null) {
        const blocked = readyBlockedByShells(shellSpans.snapshot(), readyAt);
        if (blocked) {
          logLine(blocked);
          return { ok: false, error: blocked };
        }
      }
      const summary = typeof result.result === "string" ? result.result : result.status === "finished" ? "Cursor \u4F1A\u8BDD\u5B8C\u6210" : `Cursor \u72B6\u6001\uFF1A${result.status}`;
      return { ok: result.status === "finished", summary };
    } finally {
      stopScanLog();
      if (agent) await settleWithin(8e3, agent[Symbol.asyncDispose]());
    }
  } catch (err) {
    if (cancellation?.isSkipRequested) {
      return { ok: false, error: "\u5DF2\u8DF3\u8FC7" };
    }
    if (cancellation?.isCancelled) {
      return { ok: false, error: "\u5DF2\u53D6\u6D88" };
    }
    if (err instanceof CursorAgentError) {
      return {
        ok: false,
        error: `Cursor \u542F\u52A8\u5931\u8D25\uFF1A${err.message}\uFF08retryable=${err.isRetryable}\uFF09`,
        // SDK 偶尔会把连接中断标为不可重试，保留本地网络错误兜底。
        retryable: err.isRetryable || isRetryableError(err)
      };
    }
    return {
      ok: false,
      error: `Cursor \u4F1A\u8BDD\u5F02\u5E38\uFF1A${err instanceof Error ? err.message : String(err)}`,
      retryable: isRetryableError(err)
    };
  }
}

// src/run_agent_with_retry.ts
var MAX_AGENT_ATTEMPTS = 5;
var BASE_RETRY_DELAY_MS = 1e3;
async function runAgentWithRetry(runAgent, job, cancellation, wait = sleep) {
  for (let attempt = 1; attempt <= MAX_AGENT_ATTEMPTS; attempt += 1) {
    cancellation?.throwIfCancelled();
    try {
      const result = await runAgent(job, cancellation);
      if (result.ok || cancellation?.isCancelled || cancellation?.isSkipRequested || result.error === "\u5DF2\u53D6\u6D88" || result.error === "\u5DF2\u8DF3\u8FC7" || !isRetryableAgentResult(result) || attempt >= MAX_AGENT_ATTEMPTS) {
        return result;
      }
      await waitBeforeRetry(attempt, result.error ?? "Agent \u4F1A\u8BDD\u5931\u8D25", wait);
    } catch (error) {
      if (!isRetryableError(error) || attempt >= MAX_AGENT_ATTEMPTS) throw error;
      await waitBeforeRetry(
        attempt,
        error instanceof Error ? error.message : String(error),
        wait
      );
    }
    if (cancellation?.isSkipRequested) {
      return { ok: false, error: "\u5DF2\u8DF3\u8FC7" };
    }
  }
  return { ok: false, error: "Agent \u4F1A\u8BDD\u91CD\u8BD5\u6B21\u6570\u5DF2\u8017\u5C3D" };
}
function isRetryableAgentResult(result) {
  return result.retryable === true || result.retryable !== false && isRetryableError(result.error);
}
async function waitBeforeRetry(attempt, reason, wait) {
  const delayMs = BASE_RETRY_DELAY_MS * 2 ** (attempt - 1);
  workerLog(
    `Agent \u4F1A\u8BDD\u6682\u65F6\u5931\u8D25\uFF08\u7B2C ${attempt}/${MAX_AGENT_ATTEMPTS} \u6B21\uFF09\uFF1A${reason}\uFF1B${delayMs}ms \u540E\u81EA\u52A8\u91CD\u8BD5`,
    "worker",
    "warning"
  );
  await wait(delayMs);
}

// src/session_context.ts
import {
  existsSync as existsSync6,
  mkdtempSync as mkdtempSync3,
  readFileSync as readFileSync5,
  rmSync as rmSync3,
  writeFileSync as writeFileSync4
} from "node:fs";
import { tmpdir as tmpdir3 } from "node:os";
import { isAbsolute, join as join6 } from "node:path";

// src/dispatch_scoped_tool_prompt.ts
var DISPATCH_SCOPED_TOOL_NAMES = [
  "block_card",
  "ready_to_submit",
  "submit_consultation"
];
function formatScopedKanbanToolPrompt(cardId) {
  const id = cardId.trim() || "<\u6CE8\u5165\u7684 cardId>";
  return [
    "## \u770B\u677F MCP \u6536\u5C3E\u5DE5\u5177\uFF08\u5DF2\u6CE8\u5165 schema\uFF09",
    "",
    "scoped `kanbanMCP` \u53EA\u6CE8\u518C\u4E0B\u9762\u4E09\u4E2A\u5DE5\u5177\u3002\u7981\u6B62 `GetMcpTools`\u3001`tools/list` \u6216\u62C9\u53D6\u5176\u5B83\u770B\u677F\u5DE5\u5177\u76EE\u5F55\u3002",
    "Cursor\uFF1A\u76F4\u63A5 `CallMcpTool`\uFF1BCodex\uFF1A\u76F4\u63A5\u8C03\u7528\u540C\u540D MCP \u5DE5\u5177\u3002`cardId` \u5FC5\u987B\u662F\u6CE8\u5165\u503C\u3002",
    "\u7981\u6B62\u628A ready_to_submit \u4E0E Shell\uFF08\u5C24\u5176\u662F\u6D4B\u8BD5\uFF09\u653E\u5728\u540C\u4E00\u6279\u5E76\u884C\u5DE5\u5177\u91CC\u3002\u5FC5\u987B\u7B49\u6D4B\u8BD5\u547D\u4EE4\u8FD4\u56DE exitCode=0 \u4E4B\u540E\uFF0C\u518D\u5355\u72EC\u8C03\u7528 ready_to_submit\u3002",
    "ready_to_submit / submit_consultation / block_card \u4E00\u65E6\u8FD4\u56DE\u6210\u529F\uFF0C\u7ACB\u5373\u505C\u6B62\u4E00\u5207\u5DE5\u5177\uFF1BWorker \u4F1A\u7ED3\u675F\u672C\u4F1A\u8BDD\u3002\u7981\u6B62\u518D\u6B21\u641C\u7D22\u3001\u4FEE\u6539\u6216\u91CD\u505A\u4EFB\u52A1\u3002",
    "\u5361\u7247\u7C7B\u578B\u53EA\u770B\u6CE8\u5165 JSON \u7684 cardKind / labels\uFF1AcardKind=consultation \u6216 labels \u542B consultation \u624D\u662F\u54A8\u8BE2\u5361\uFF1B\u5426\u5219\u4E00\u5F8B\u662F\u5B9E\u65BD\u5361\u3002\u7981\u6B62\u6839\u636E\u6807\u9898\u6216\u5907\u6CE8\u50CF\u4E0D\u50CF\u95EE\u9898\u6765\u6539\u5224\u3002",
    "Shell \u7684 working_directory \u5FC5\u987B\u4E0E\u547D\u4EE4\u91CC\u7684\u76F8\u5BF9\u8DEF\u5F84\u4E00\u81F4\uFF1Acwd \u5DF2\u662F app \u65F6\u4E0D\u8981\u518D\u5199 app/lib\u3002flutter test / dart test \u79D2\u9000\u4E0D\u5F97\u89C6\u4E3A\u901A\u8FC7\u3002",
    "",
    "```json",
    JSON.stringify(
      {
        server: "kanbanMCP",
        tools: {
          ready_to_submit: {
            required: [
              "cardId",
              "completedChecklistIds",
              "completedFeedbackIds"
            ],
            properties: {
              cardId: id,
              completedChecklistIds: "\u672C\u8F6E\u5B8C\u6210\u7684 checklist id\uFF1B\u65E0\u5219 []",
              completedFeedbackIds: "\u672C\u8F6E\u5B8C\u6210\u7684 feedback id\uFF1B\u65E0\u5219 []",
              manualVerificationReason: "\u65E0\u6CD5\u81EA\u52A8\u9A8C\u8BC1\u65F6\u624D\u4F20",
              gitRevertCommit: "\u4EC5\u5F53 workItems \u660E\u786E\u8981\u6C42 revert \u65F6\u4F20 7\u201364 \u4F4D\u54C8\u5E0C"
            },
            example: {
              cardId: id,
              completedChecklistIds: [],
              completedFeedbackIds: []
            }
          },
          submit_consultation: {
            required: ["cardId", "responseMarkdown"],
            example: {
              cardId: id,
              responseMarkdown: "\u54A8\u8BE2\u7B54\u590D Markdown"
            }
          },
          block_card: {
            required: ["cardId"],
            properties: { reason: "\u963B\u585E\u539F\u56E0" },
            example: { cardId: id, reason: "\u65E0\u6CD5\u5B8C\u6210\u7684\u539F\u56E0" }
          }
        }
      },
      null,
      2
    ),
    "```"
  ].join("\n");
}

// src/user_rule_canary.ts
var WORKER_USER_RULES_BEGIN = "KANBAN_WORKER_USER_RULES_BEGIN";
var WORKER_USER_RULES_END = "KANBAN_WORKER_USER_RULES_END";
function wrapWorkerUserRules(text) {
  const body = text.trim() || "\u672A\u53D1\u73B0\u7528\u6237 ~/.cursor/rules\u3002";
  return [WORKER_USER_RULES_BEGIN, body, WORKER_USER_RULES_END].join("\n");
}

// src/worker_glob_policy.ts
var DISPATCH_SEARCH_POLICY = `## \u641C\u7D22\u8303\u56F4\uFF08Worker\uFF09

\u5B9A\u4F4D\u4EE3\u7801\u65F6 MUST \u7528 grep \u6216\u5E26\u6587\u4EF6\u540D/\u76EE\u5F55\u9650\u5B9A\u7684 glob\uFF0C\u5E76\u6307\u5B9A\u5B50\u76EE\u5F55\u3002
MUST NOT \u5BF9\u4ED3\u5E93\u6839\u505A\u65E0\u754C glob\uFF08\`**\`\u3001\`**/*\`\u3001\`**/*.*\`\uFF09\u3002
MUST NOT \u628A\u65E0\u754C glob \u4E0E grep \u5E76\u884C\uFF1Bgrep \u5DF2\u8FD4\u56DE\u5019\u9009\u6587\u4EF6\u65F6\u76F4\u63A5\u8BFB\u90A3\u4E9B\u8DEF\u5F84\u3002
MUST NOT \u628A glob \u76EE\u6807\u6307\u5230 \`.git\`\u3001\`.svn\` \u6216 \`build\`\u3002
\u5361\u7247\u91CC\u7684\u754C\u9762\u5165\u53E3\u6309\u4EA7\u54C1\u8868\u9762\u843D\u5230\u529F\u80FD\u76EE\u5F55\uFF1A\u770B\u677F\u5361\u7247\u8BE6\u60C5\uFF08\u542B\u6587\u4EF6\u9644\u4EF6\u4E09\u4E2A\u70B9\u83DC\u5355\uFF09\u5728 \`app/lib/features/kanban/\`\uFF1BAgent \u8C03\u5EA6\u7A97\u53E3\u672C\u8EAB\u624D\u5728 \`agent_dispatch/\`\u3002\u4E0D\u8981\u628A\u300C\u5DE5\u4F5C\u53F0\u300D\u9ED8\u8BA4\u7406\u89E3\u6210\u5FC5\u987B\u5148\u641C\u8C03\u5EA6\u76EE\u5F55\u3002
`;

// src/session_context.ts
function readBatchArchitecture(cwd) {
  const path = join6(cwd, "docs", "Architecture.md");
  if (!existsSync6(path)) return "\u4ED3\u5E93\u672A\u63D0\u4F9B docs/Architecture.md\u3002";
  return readFileSync5(path, "utf8");
}
function createSessionContext(options) {
  const tempDir = mkdtempSync3(
    join6(options.tempRoot ?? tmpdir3(), "kanban-agent-session-")
  );
  const attachmentPaths = [];
  const payload = structuredClone(options.claim.payload);
  const fileAttachments = Array.isArray(payload.fileAttachments) ? payload.fileAttachments : [];
  for (let index = 0; index < fileAttachments.length; index += 1) {
    const raw = fileAttachments[index];
    if (!isRecord2(raw)) continue;
    const content = typeof raw.contentBase64 === "string" ? raw.contentBase64 : "";
    delete raw.contentBase64;
    if (!content || raw.included === false) continue;
    const fileName = safeFileName(
      typeof raw.fileName === "string" ? raw.fileName : `attachment-${index}.bin`,
      `attachment-${index}.bin`
    );
    const path = uniquePath(tempDir, `${index + 1}-${fileName}`);
    writeFileSync4(path, Buffer.from(content, "base64"));
    raw.absolutePath = path;
    attachmentPaths.push(path);
  }
  const imagePaths = [];
  for (let index = 0; index < options.claim.images.length; index += 1) {
    const image = options.claim.images[index];
    const path = join6(
      tempDir,
      `image-${index + 1}.${extensionForMime(image.mimeType)}`
    );
    writeFileSync4(path, Buffer.from(image.data, "base64"));
    imagePaths.push(path);
  }
  const prompt = [
    options.basePrompt.trim(),
    "",
    "# Worker \u6CE8\u5165\u7684\u672C\u8F6E\u4E0A\u4E0B\u6587",
    "",
    "\u672C\u8F6E\u5361\u7247\u5DF2\u9886\u53D6\u3002\u4EE5\u4E0B\u4E0A\u4E0B\u6587\u662F\u552F\u4E00\u4EFB\u52A1\u8303\u56F4\uFF1B\u4E0D\u8981\u518D\u6B21\u8BFB\u53D6 Skill \u6216\u9886\u53D6\u5176\u4ED6\u5361\u7247\u3002",
    "",
    "\u5361\u7247\u7C7B\u578B\u53EA\u7531 JSON \u7684 `cardKind` \u4E0E `labels` \u51B3\u5B9A\uFF1A`consultation` \u4E3A\u54A8\u8BE2\u5361\uFF0C\u5426\u5219\u4E3A\u5B9E\u65BD\u5361\u3002\u672A\u6253\u54A8\u8BE2\u6807\u7B7E\u65F6\uFF0C\u5373\u4F7F\u6807\u9898\u50CF\u63D0\u95EE\u3001\u6CA1\u6709\u6E05\u5355\uFF0C\u4E5F\u5FC5\u987B\u5F53\u5B9E\u65BD\u5361\u505A\u5B8C\u5E76 `ready_to_submit`\u3002\u4E0D\u8981\u81EA\u884C\u6539\u5224\u3002",
    "",
    DISPATCH_SEARCH_POLICY.trim(),
    "",
    "## \u5361\u7247\u4E0A\u4E0B\u6587\uFF08JSON\uFF09",
    "",
    "```json",
    JSON.stringify(payload, null, 2),
    "```",
    "",
    formatScopedKanbanToolPrompt(cardIdFromPayload(payload)),
    "",
    "## \u4E34\u65F6\u9644\u4EF6\u7EDD\u5BF9\u8DEF\u5F84",
    "",
    ...attachmentPaths.length === 0 ? ["- \u65E0\u6587\u4EF6\u9644\u4EF6"] : attachmentPaths.map((path) => `- \u6587\u4EF6\uFF1A${path}`),
    ...imagePaths.length === 0 ? ["- \u65E0\u56FE\u7247\u4E34\u65F6\u8DEF\u5F84"] : imagePaths.map((path) => `- \u56FE\u7247\uFF1A${path}`),
    "",
    "\u8FD9\u4E9B\u8DEF\u5F84\u4F4D\u4E8E\u7CFB\u7EDF\u4E34\u65F6\u4F1A\u8BDD\u76EE\u5F55\uFF0C\u53EA\u5728\u672C\u8F6E\u6709\u6548\uFF1B\u4E0D\u8981\u590D\u5236\u5230\u4ED3\u5E93\u3002",
    "",
    "## \u5B8C\u6574\u7528\u6237 Rule",
    "",
    wrapWorkerUserRules(options.userRules ?? ""),
    "",
    "## \u5DF2\u7F13\u5B58\u7684 docs/Architecture.md",
    "",
    options.architecture.trim(),
    "",
    "\u4EE5\u4E0A\u6B63\u6587\u5DF2\u6EE1\u8DB3\u7528\u6237\u89C4\u5219 / AGENTS.md \u4E2D\u7684\u300C\u5F00\u53D1\u524D\u5FC5\u8BFB Architecture.md\u300D\u3002\u7981\u6B62\u518D\u6253\u5F00\u8BE5\u6587\u4EF6\u3002ADR\u3001docs/Systems\u3001CONTEXT.md \u9700\u8981\u65F6\u4ECD\u53EF\u8BFB\u3002"
  ].join("\n");
  return {
    prompt,
    images: options.claim.images,
    attachmentPaths: [...attachmentPaths, ...imagePaths],
    tempDir,
    cleanup: () => {
      rmSync3(tempDir, { recursive: true, force: true });
    }
  };
}
function cardIdFromPayload(payload) {
  const value = payload.cardId;
  return typeof value === "string" ? value.trim() : "";
}
function isRecord2(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function safeFileName(value, fallback) {
  const normalized = value.replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_").replace(/[. ]+$/g, "").trim();
  return normalized || fallback;
}
function uniquePath(root, fileName) {
  const path = join6(root, fileName);
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

// src/user_rules.ts
import {
  existsSync as existsSync7,
  readFileSync as readFileSync6,
  readdirSync,
  statSync as statSync2
} from "node:fs";
import { homedir as homedir4 } from "node:os";
import { join as join7, relative } from "node:path";
var RULE_EXTENSIONS = /* @__PURE__ */ new Set([".md", ".mdc"]);
function readUserCursorRules(root = join7(homedir4(), ".cursor", "rules")) {
  if (!existsSync7(root)) return { text: "", count: 0, bytes: 0 };
  const paths = collectRulePaths(root).sort((a, b) => a.localeCompare(b));
  const sections = [];
  let bytes = 0;
  for (const path of paths) {
    const content = readFileSync6(path, "utf8");
    bytes += Buffer.byteLength(content, "utf8");
    sections.push(
      [`## \u7528\u6237 Rule\uFF1A${relative(root, path).replaceAll("\\", "/")}`, "", content].join("\n")
    );
  }
  return {
    text: sections.join("\n\n"),
    count: paths.length,
    bytes
  };
}
function collectRulePaths(root) {
  const result = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join7(root, entry.name);
    if (entry.isDirectory()) {
      result.push(...collectRulePaths(path));
      continue;
    }
    if (!entry.isFile() || !statSync2(path).isFile()) continue;
    const dot = entry.name.lastIndexOf(".");
    const extension = dot < 0 ? "" : entry.name.slice(dot).toLowerCase();
    if (RULE_EXTENSIONS.has(extension)) result.push(path);
  }
  return result;
}

// src/run_batch.ts
import { readFileSync as readFileSync7 } from "node:fs";
var defaultDependencies = {
  connectMcp: async (endpoint) => {
    const client = new KanbanMcpClient();
    await client.connect(endpoint);
    return client;
  },
  inspectGit: inspectGitWorkingTree,
  readArchitecture: readBatchArchitecture,
  readUserRules: readUserCursorRules,
  createContext: createSessionContext,
  runAgent: (roundJob, cancellation) => roundJob.engine === "codex" ? runCodex(roundJob, cancellation) : runCursor(roundJob, cancellation)
};
async function runBatch(job, cancellation, dependencies = defaultDependencies) {
  const limit = Math.max(1, Math.min(999, Math.trunc(job.cardLimit)));
  const architecture = dependencies.readArchitecture(job.cwd);
  const userRules = dependencies.readUserRules?.() ?? {
    text: "",
    count: 0,
    bytes: 0
  };
  const mcp = await dependencies.connectMcp(job.mcpEndpoint);
  let processedCards = 0;
  workerLog(`Worker \u6279\u6B21\u542F\u52A8\uFF1Aendpoint=${job.mcpEndpoint} limit=${limit}`);
  workerLog(
    `\u7528\u6237 Rule \u6CE8\u5165\uFF1A${userRules.count} \u4E2A\uFF0C${userRules.bytes} bytes\uFF1B\u7528\u6237 Skill \u4E0D\u5199\u5165 prompt`
  );
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
      job
    );
    if (!recovery.ok) {
      return { ...recovery, processedCards };
    }
    processedCards += recovery.processedCards ?? 0;
    for (let index = 1; index <= limit; index += 1) {
      if (cancellation?.shouldStopAfterCurrentSession) {
        return cancellation.isCancelled ? cancelledResult() : drainedResult();
      }
      const liveJob = readLiveJob(job);
      const peek = await mcp.callJson("peek_next_card", {
        ...liveJob.projectId ? { projectId: liveJob.projectId } : {}
      });
      if (peek.found !== true) {
        return completedResult(processedCards, "\u5F53\u524D\u65E0\u66F4\u591A\u5361\u7247");
      }
      const preview = mergeJobWithCardOverrides(liveJob, peek);
      const tree = dependencies.inspectGit(job.cwd);
      if (tree.kind === "dirty" && preview.allowDirtyWorkspace === true) {
        workerLog(`\u5DF2\u5141\u8BB8\u810F\u5DE5\u4F5C\u533A\uFF0C\u7EE7\u7EED\u9886\u53D6\uFF1A
${tree.output}`);
      } else {
        const treeError = gitPreflightError(tree);
        if (treeError) {
          return { ok: false, error: treeError, processedCards };
        }
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
      const roundLabel = limit >= 999 ? `${index}` : `${index}/${limit}`;
      workerLog(`\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 Worker \u5355\u5361\u8F6E\u6B21 ${roundLabel} \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500`);
      const cardId = requiredString(claim.payload, "cardId");
      const sessionId = requiredString(claim.payload, "sessionId");
      const agentEndpointUrl = requiredString(
        claim.payload,
        "agentEndpointUrl"
      );
      let scoped;
      let context;
      let terminalRecorded = false;
      let allowDirtyWorkspace = preview.allowDirtyWorkspace === true;
      let postAgent = false;
      try {
        scoped = await dependencies.connectMcp(agentEndpointUrl);
        const tools = await scoped.listTools();
        if (JSON.stringify(tools) !== JSON.stringify(DISPATCH_SCOPED_TOOL_NAMES)) {
          throw new Error(
            `scoped MCP \u5DE5\u5177\u95E8\u7981\u5931\u8D25\uFF1A\u5B9E\u9645=${tools.join(",")}\uFF0C\u671F\u671B=${DISPATCH_SCOPED_TOOL_NAMES.join(",")}`
          );
        }
        context = dependencies.createContext({
          basePrompt: job.prompt,
          architecture,
          userRules: userRules.text,
          claim
        });
        const overridden = mergeJobWithCardOverrides(liveJob, claim.payload);
        allowDirtyWorkspace = overridden.allowDirtyWorkspace === true;
        const roundJob = {
          ...overridden,
          prompt: context.prompt,
          round: {
            cardId,
            sessionId,
            agentEndpointUrl,
            images: context.images,
            attachmentPaths: context.attachmentPaths,
            cardContext: claim.payload,
            projectMcpTags: parseProjectMcpTags(claim.payload),
            reportShellSpan: async (span) => {
              await mcp.callJson(
                "dispatch_report_shell_span",
                toShellSpanReportPayload({
                  workerToken: job.workerToken,
                  sessionId,
                  span
                })
              );
            },
            peekDispatchTerminal: async () => {
              const status2 = await mcp.callJson("dispatch_agent_session_status", {
                workerToken: job.workerToken
              });
              const pending2 = asRecord7(status2.pending);
              if (String(pending2?.status ?? "") === "declared") {
                return "declared";
              }
              const projectId2 = String(
                status2.projectId ?? claim.payload.projectId ?? job.projectId ?? ""
              ).trim();
              const latest2 = await mcp.callJson("get_card", {
                cardId,
                ...projectId2 ? { projectId: projectId2 } : {}
              });
              const state2 = cardState(latest2);
              return state2 === "active" ? "none" : state2;
            }
          }
        };
        logModelOverride(liveJob, roundJob, cardId);
        logClaimedCard(claim.payload);
        workerLog("Worker \u6B63\u5728\u5B9E\u65BD\u5F53\u524D\u5361\u7247");
        const agentResult = await runAgentWithRetry(
          dependencies.runAgent,
          roundJob,
          cancellation,
          dependencies.sleep
        );
        if (cancellation?.isSkipRequested || agentResult.error === "\u5DF2\u8DF3\u8FC7") {
          cancellation?.clearSkipRequest();
          await mcp.callJson("dispatch_skip_agent_session", {
            workerToken: job.workerToken,
            sessionId,
            reason: "\u7528\u6237\u8BF7\u6C42\u8DF3\u8FC7\u5F53\u524D\u5361\u7247"
          });
          terminalRecorded = true;
          const afterSkip = dependencies.inspectGit(job.cwd);
          if (!allowDirtyWorkspace) {
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
        postAgent = true;
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
        const pending = asRecord7(status.pending);
        if (state === "blocked") {
          return {
            ok: false,
            error: `\u5361\u7247 ${cardId} \u5DF2\u8FDB\u5165\u963B\u585E\u4E2D\uFF0CWorker \u505C\u6B62\u6279\u6B21`,
            processedCards
          };
        }
        if (state === "verify" && pending == null) {
          processedCards += 1;
          workerLog(`\u54A8\u8BE2\u5361 ${cardId} \u5DF2\u9001\u4EA4\u9A8C\u8BC1`, "worker", "success");
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
        workerLog("Worker \u6B63\u5728\u63D0\u4EA4\u5F53\u524D\u5361\u7247");
        const finalized = await validateAndFinalize(
          mcp,
          job,
          pending
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
        workerLog(`\u5361\u7247 ${cardId} \u5DF2\u9A8C\u8BC1\u3001\u63D0\u4EA4\u5E76\u9001\u4EA4\u4EBA\u5DE5\u9A8C\u8BC1`, "worker", "success");
        if (cancellation?.shouldStopAfterCurrentSession) {
          return cancellation.isCancelled ? cancelledResult() : drainedResult();
        }
      } catch (error) {
        const reason = error instanceof WorkerCancelledError ? "\u7528\u6237\u53D6\u6D88\u5F53\u524D Agent \u4F1A\u8BDD" : `${postAgent ? "Worker \u6536\u5C3E\u5931\u8D25" : "Agent \u4F1A\u8BDD\u5F02\u5E38"}\uFF1A${error instanceof Error ? error.message : String(error)}`;
        if (!terminalRecorded) {
          await recordRoundFailure(
            mcp,
            job,
            sessionId,
            reason,
            error instanceof WorkerCancelledError
          );
        }
        const tree2 = dependencies.inspectGit(job.cwd);
        const dirtySuffix = allowDirtyWorkspace || postAgent ? "" : tree2.kind === "dirty" ? `
\u5DE5\u4F5C\u533A\u4E0D\u5E72\u51C0\uFF0C\u505C\u6B62\u6279\u6B21\uFF1A
${tree2.output}` : tree2.kind === "unknown" ? `
\u65E0\u6CD5\u5224\u65AD\u5DE5\u4F5C\u533A\u72B6\u6001\uFF0C\u505C\u6B62\u6279\u6B21\uFF1A${tree2.output}` : "";
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
async function recoverPendingSessions(mcp, job) {
  const listed = await mcp.callJson("dispatch_list_pending", {
    workerToken: job.workerToken
  });
  const pending = Array.isArray(listed.pending) ? listed.pending : [];
  let processedCards = 0;
  for (const raw of pending) {
    const record = asRecord7(raw);
    if (!record) continue;
    const sessionId = requiredString(record, "sessionId");
    const recovered = await mcp.callJson("dispatch_recover", {
      workerToken: job.workerToken,
      sessionId
    });
    const result = await validateAndFinalize(
      mcp,
      job,
      recovered
    );
    if (!result.ok) return { ...result, processedCards };
    processedCards += 1;
    workerLog(`\u5DF2\u6062\u590D pending \u4F1A\u8BDD ${sessionId}`, "worker", "success");
  }
  return { ok: true, processedCards };
}
async function validateAndFinalize(mcp, job, pending) {
  const sessionId = requiredString(pending, "sessionId");
  const cardId = requiredString(pending, "cardId");
  let status = String(pending.status ?? "");
  if (status === "declared") {
    workerLog("\u9A8C\u8BC1\u5DF2\u7531 Agent \u4F1A\u8BDD\u5B8C\u6210\uFF0CWorker \u4E0D\u518D\u590D\u8DD1\u6D4B\u8BD5");
    const recorded = await mcp.callJson("dispatch_record_validation_results", {
      workerToken: job.workerToken,
      sessionId,
      results: []
    });
    status = String(recorded.status ?? "");
    if (status === "failed") {
      const reason = String(recorded.error ?? "\u9A8C\u8BC1\u5931\u8D25");
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
  workerLog("Worker \u6B63\u5728\u63D0\u4EA4\u5E76\u9001\u4EA4\u9A8C\u8BC1");
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
      `\u8BB0\u5F55\u4F1A\u8BDD\u5931\u8D25\u72B6\u6001\u5931\u8D25\uFF1A${error instanceof Error ? error.message : String(error)}`,
      "worker",
      "warning"
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
function asRecord7(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}
function completedResult(processedCards, reason) {
  workerLog(`Worker \u6279\u6B21\u5B8C\u6210\uFF1A${reason}\uFF1B\u5DF2\u5904\u7406 ${processedCards} \u5F20`, "worker", "success");
  return {
    ok: true,
    summary: `Worker \u6279\u6B21\u5B8C\u6210\uFF1A${reason}\uFF1B\u5DF2\u5904\u7406 ${processedCards} \u5F20`,
    processedCards
  };
}
function logClaimedCard(payload) {
  const items = Array.isArray(payload.workItems) ? payload.workItems : [];
  let title = "";
  const details = [];
  for (const raw of items) {
    const record = asRecord7(raw);
    if (!record) continue;
    const kind = String(record.kind ?? "");
    const text = String(record.text ?? "").trim();
    if (!text) continue;
    if (kind === "title" && !title) title = text;
    else details.push(text);
  }
  workerLog(`\u5F53\u524D\u5361\u7247\uFF1A${title || String(payload.cardId ?? "\u672A\u547D\u540D\u5361\u7247")}`);
  if (details.length > 0) {
    const detail = details.join("\n").slice(0, 800);
    workerLog(`\u5F53\u524D\u4EFB\u52A1\uFF1A${detail}`);
  }
}
function readLiveJob(job) {
  if (!job.liveFile) return job;
  try {
    const raw = JSON.parse(readFileSync7(job.liveFile, "utf8"));
    return applyLiveJobOverlay(job, raw);
  } catch {
    return job;
  }
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
function formatListModelsError(err) {
  if (err && typeof err === "object" && "message" in err) {
    const message = String(err.message).trim();
    if (message) return `Cursor.models.list \u5931\u8D25\uFF1A${message}`;
  }
  return `Cursor.models.list \u5931\u8D25\uFF1A${String(err)}`;
}
function writeResult(outPath, result) {
  writeFileSync5(outPath, JSON.stringify(result, null, 2), "utf8");
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
    models = await withRetry(
      "\u62C9\u53D6\u6A21\u578B\u5217\u8868",
      () => Cursor3.models.list({ apiKey }),
      {
        onRetry: ({ operation, attempt, maxAttempts, delayMs }) => {
          console.error(
            `${operation} \u5931\u8D25\uFF08\u7B2C ${attempt}/${maxAttempts} \u6B21\uFF09\uFF0C${delayMs}ms \u540E\u91CD\u8BD5\u2026`
          );
        }
      }
    );
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
  const job = JSON.parse(readFileSync8(jobPath, "utf8"));
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
  await runJob(resolve(argv[idx + 1]));
}
main().catch((err) => {
  console.error(err);
  process.exit(1);
});
