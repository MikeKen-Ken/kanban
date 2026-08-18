// src/cli.ts
import { readFileSync as readFileSync7, writeFileSync as writeFileSync4 } from "node:fs";
import { resolve } from "node:path";
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
  if (rawParameters.length > 0) {
    const allowed = new Set(
      parameters.map((item) => String(item.id ?? "").trim()).filter(Boolean)
    );
    for (const id of [...byId.keys()]) {
      if (!allowed.has(id)) byId.delete(id);
    }
    for (const parameter of parameters) {
      const id = String(parameter.id ?? "").trim();
      if (!id || byId.has(id)) continue;
      const value = conservativeParamValue(id, parameterValueList(parameter.values));
      if (value) byId.set(id, { id, value });
    }
  } else if (cardModel) {
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

// src/run_codex.ts
import { spawn as spawn2 } from "node:child_process";
import {
  existsSync as existsSync3,
  mkdtempSync as mkdtempSync2,
  readFileSync as readFileSync2,
  rmSync,
  writeFileSync as writeFileSync2
} from "node:fs";
import { tmpdir as tmpdir2 } from "node:os";
import { dirname, join as join2 } from "node:path";
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
    event = asRecord2(JSON.parse(line)) ?? {};
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
      return recordsFromUsage(asRecord2(event.usage));
    case "turn.failed": {
      const message = pickString(asRecord2(event.error), "message") || pickString(event, "message") || "Codex \u56DE\u5408\u5931\u8D25";
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
      return recordsFromCodexItem(type, asRecord2(event.item) ?? {});
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
      return toRecords(expandMultiline("\u52A9\u624B\uFF1A", pickString(item, "text")), "ai");
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
  const parts = changes.map((entry) => asRecord2(entry)).filter((entry) => entry != null).map((entry) => {
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
    const err = pickString(asRecord2(item.error), "message") || pickString(item, "error") || "\u8C03\u7528\u5931\u8D25";
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
  const parts = items.map((entry) => asRecord2(entry)).filter((entry) => entry != null).map((entry) => {
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
  const record = asRecord2(result);
  if (!record) return usefulJson(result);
  const content = record.content;
  if (Array.isArray(content)) {
    const texts = content.map((block) => asRecord2(block)).filter((block) => block != null).filter((block) => block.type === "text" && typeof block.text === "string").map((block) => String(block.text).trim()).filter(Boolean);
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
function asRecord2(value) {
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
  tavily: ["tavily"],
  unity: ["unitymcp", "unityMCP"],
  cocos: ["cocos-creator"],
  node_repl: ["node_repl"]
};
var ALWAYS_ENABLED_MCP_SERVERS = ["hubMCP"];
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
  const allowed = new Set(ALWAYS_ENABLED_MCP_SERVERS);
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

// src/worker_log.ts
import { writeSync } from "node:fs";
function workerLog(line, source = "worker", level = "info") {
  const prefix = level === "info" ? `[${source}]` : `[${level}] [${source}]`;
  for (const part of line.split(/\r?\n/)) {
    writeSync(1, `${prefix} ${part}
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
  const temp = mkdtempSync2(join2(tmpdir2(), "kanban-codex-"));
  const promptFile = join2(temp, "prompt.txt");
  const lastMessageFile = join2(temp, "last.txt");
  try {
    writeFileSync2(promptFile, job.prompt, "utf8");
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
      const logState = createCodexLogState();
      const stdoutLines = createLineBuffer((line) => {
        workerLogRecords(recordsFromCodexJsonLine(line, logState));
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
      child.on("error", reject);
      if (!child.stdin) {
        reject(new Error("Codex stdin \u4E0D\u53EF\u7528"));
        return;
      }
      child.stdin.write(readFileSync2(promptFile));
      child.stdin.end();
      child.on("close", (exitCode) => {
        stdoutLines.flush();
        stderrLines.flush();
        if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
          resolvePromise(130);
          return;
        }
        resolvePromise(exitCode ?? 1);
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
      summary = readFileSync2(lastMessageFile, "utf8").trim();
    } catch {
      summary = void 0;
    }
    workerLog(`Codex exec exitCode=${code} elapsedMs=${Date.now() - startedAt}`);
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

// src/run_cursor.ts
import { mkdirSync as mkdirSync2 } from "node:fs";
import { homedir as homedir3 } from "node:os";
import { join as join4 } from "node:path";
import { Agent, CursorAgentError, JsonlLocalAgentStore } from "@cursor/sdk";

// src/cursor_mcp_servers.ts
import { existsSync as existsSync4, readFileSync as readFileSync3 } from "node:fs";
import { homedir as homedir2 } from "node:os";
import { join as join3 } from "node:path";
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
    userJson: readOptionalFile(join3(home, ".cursor", "mcp.json")),
    projectJson: readOptionalFile(join3(options.cwd, ".cursor", "mcp.json")),
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
  if (!existsSync4(path)) return null;
  try {
    return readFileSync3(path, "utf8");
  } catch {
    return null;
  }
}
function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

// src/run_diagnostics.ts
var DEFAULT_AGENT_RUN_BUDGET = {
  maxSteps: 60,
  maxToolCalls: 40
};
var AgentRunDiagnostics = class {
  steps = 0;
  toolCalls = 0;
  repeatedToolCalls = 0;
  signatures = /* @__PURE__ */ new Map();
  reads = /* @__PURE__ */ new Map();
  budget;
  constructor(budget = DEFAULT_AGENT_RUN_BUDGET) {
    this.budget = budget;
  }
  recordStep(input) {
    this.steps += 1;
    if (input.type === "toolCall") {
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
    if (this.steps > this.budget.maxSteps) {
      return `\u6B65\u9AA4\u6570\u8D85\u8FC7\u4E0A\u9650 ${this.budget.maxSteps}`;
    }
    if (this.toolCalls > this.budget.maxToolCalls) {
      return `\u5DE5\u5177\u8C03\u7528\u8D85\u8FC7\u4E0A\u9650 ${this.budget.maxToolCalls}`;
    }
    return void 0;
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
function asRecord3(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : void 0;
}
function pickString2(message, ...keys) {
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
    return asRecord3(JSON.parse(trimmed));
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
function toolPayload(step) {
  return asRecord3(step.message) ?? asRecord3(step.toolCall) ?? asRecord3(step.call) ?? asRecord3(step.tool) ?? asRecord3(asRecord3(step.message)?.toolCall) ?? asRecord3(asRecord3(step.message)?.call);
}
function extractToolDetail(payload) {
  if (!payload) return "";
  const nested = asRecord3(payload.args) ?? asRecord3(payload.arguments) ?? asRecord3(payload.input) ?? asRecord3(payload.params) ?? asRecord3(asRecord3(payload.function)?.arguments) ?? parseJsonRecord(payload.args) ?? parseJsonRecord(payload.arguments) ?? parseJsonRecord(asRecord3(payload.function)?.arguments);
  const command = pickString2(
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
    const nestedCommand = pickString2(
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
  const record = asRecord3(step) ?? {};
  const type = String(record.type ?? "unknown");
  const message = toolPayload(record);
  switch (type) {
    case "assistantMessage":
      return {
        lines: expandMultiline2("\u52A9\u624B\uFF1A", String(message?.text ?? "")),
        source: "ai"
      };
    case "thinkingMessage": {
      const text = pickString2(message, "text", "thinking", "content");
      return {
        lines: text ? expandMultiline2("\u601D\u8003\uFF1A", text) : [],
        source: "ai"
      };
    }
    case "toolCall": {
      const toolName = pickString2(message, "name", "toolName", "functionName", "type") || pickString2(record, "name", "toolName") || "tool";
      const detail = extractToolDetail(message);
      if (!detail) {
        return {
          lines: [],
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
      const toolName = pickString2(message, "name", "toolName", "type") || "tool";
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
      const command = extractToolDetail(message) || pickString2(message, "command", "text");
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
    const diagnostics = new AgentRunDiagnostics(DEFAULT_AGENT_RUN_BUDGET);
    let budgetError;
    let activeRun;
    const storeDir = join4(homedir3(), ".cursor", "kanban-agent-jsonl-store");
    mkdirSync2(storeDir, { recursive: true });
    const mcp = loadCursorMcpServers({
      cwd: job.cwd,
      scopedKanbanUrl: agentMcpUrl,
      projectMcpTags: job.round.projectMcpTags
    });
    const hasProjectWebMcp = job.round.projectMcpTags.some(
      (tag) => tag === "tavily" || tag === "chrome-devtools"
    );
    const disallowedTools = [
      "task",
      ...hasProjectWebMcp ? ["webSearch", "webFetch"] : []
    ];
    logLine(
      `\u672C\u5730\u8FD0\u884C\uFF1AJSONL \u5B58\u50A8=${storeDir}\uFF1B\u6C99\u7BB1${job.enableSandbox === true ? "\u5F00\u542F" : "\u5173\u95ED"}\uFF1B\u5408\u5E76 MCP\uFF08${mcp.names.join(", ") || "\u65E0"}\uFF09\uFF1BkanbanMCP \u5F3A\u5236\u4E3A scoped\uFF08${agentMcpUrl}\uFF09\uFF1B\u7981\u7528\u5DE5\u5177=${disallowedTools.join(",")}\uFF1BsettingSources=project\uFF08\u7528\u6237 Rule \u5DF2\u5B8C\u6574\u6CE8\u5165\uFF1B\u4E0D\u52A0\u8F7D\u7528\u6237 Skill\uFF1B\u4FDD\u7559\u9879\u76EE\u89C4\u5219 / Skill / Hooks\uFF09`
    );
    const agent = await Agent.create({
      apiKey,
      model: {
        id: modelId,
        ...params ? { params } : {}
      },
      mcpServers: mcp.servers,
      disallowedTools,
      local: {
        cwd: job.cwd,
        // 用户 Rule 已由 Worker 完整注入；只让 SDK 加载项目规则 / Skill / Hooks，
        // 避免把所有个人 Skill 一并加入每个单卡会话。
        settingSources: ["project"],
        store: new JsonlLocalAgentStore(storeDir),
        // 无头 Worker 无人点批准；Auto-review 会拦 ready_to_submit 导致整卡失败。
        autoReview: false,
        sandboxOptions: { enabled: job.enableSandbox === true }
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
            const exceeded = diagnostics.recordStep({
              type: String(step.type),
              toolName: described.toolName,
              detail: described.detail
            });
            if (exceeded && !budgetError) {
              budgetError = exceeded;
              logLine(`Agent \u9884\u7B97\u8D85\u9650\uFF1A${exceeded}\uFF0C\u6B63\u5728\u7EC8\u6B62\u5F53\u524D\u4F1A\u8BDD`);
              void activeRun?.cancel().catch(() => void 0);
            }
            if (described.lines.length > 0) {
              logLines(described.lines, described.source);
            }
          } catch {
            logLine("\u6536\u5230\u4E00\u6B65\u8FDB\u5EA6");
          }
        }
      });
      activeRun = run;
      if (budgetError) await run.cancel().catch(() => void 0);
      cancellation?.onCancel(() => {
        void run.cancel().catch(() => void 0);
      });
      if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
        await run.cancel().catch(() => void 0);
      }
      const result = await run.wait();
      const metrics = diagnostics.snapshot();
      logLine(formatAgentRunDiagnostics(metrics));
      logLine(
        `Cursor run id=${result.id} status=${result.status} steps=${stepCount} tools=${toolCallCount} elapsedMs=${Date.now() - startedAt}`
      );
      if (result.usage) {
        logLine(formatSessionTokenLog(result.usage, metrics));
      }
      if (budgetError) {
        return { ok: false, error: `Agent \u9884\u7B97\u8D85\u9650\uFF1A${budgetError}` };
      }
      if (cancellation?.isSkipRequested) {
        logLine("Cursor \u4F1A\u8BDD\u5DF2\u7531\u7528\u6237\u8DF3\u8FC7", "worker");
        return { ok: false, error: "\u5DF2\u8DF3\u8FC7" };
      }
      if (cancellation?.isCancelled || result.status === "cancelled") {
        logLine("Cursor \u4F1A\u8BDD\u5DF2\u7531\u7528\u6237\u505C\u6B62", "worker");
        return { ok: false, error: "\u5DF2\u53D6\u6D88" };
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
  existsSync as existsSync5,
  mkdtempSync as mkdtempSync3,
  readFileSync as readFileSync4,
  rmSync as rmSync2,
  writeFileSync as writeFileSync3
} from "node:fs";
import { tmpdir as tmpdir3 } from "node:os";
import { isAbsolute, join as join5 } from "node:path";
function readBatchArchitecture(cwd) {
  const path = join5(cwd, "docs", "Architecture.md");
  if (!existsSync5(path)) return "\u4ED3\u5E93\u672A\u63D0\u4F9B docs/Architecture.md\u3002";
  return readFileSync4(path, "utf8");
}
function createSessionContext(options) {
  const tempDir = mkdtempSync3(
    join5(options.tempRoot ?? tmpdir3(), "kanban-agent-session-")
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
    writeFileSync3(path, Buffer.from(content, "base64"));
    raw.absolutePath = path;
    attachmentPaths.push(path);
  }
  const imagePaths = [];
  for (let index = 0; index < options.claim.images.length; index += 1) {
    const image = options.claim.images[index];
    const path = join5(
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
    "## \u5B8C\u6574\u7528\u6237 Rule",
    "",
    options.userRules?.trim() || "\u672A\u53D1\u73B0\u7528\u6237 ~/.cursor/rules\u3002",
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
      rmSync2(tempDir, { recursive: true, force: true });
    }
  };
}
function isRecord2(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function safeFileName(value, fallback) {
  const normalized = value.replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_").replace(/[. ]+$/g, "").trim();
  return normalized || fallback;
}
function uniquePath(root, fileName) {
  const path = join5(root, fileName);
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
  existsSync as existsSync6,
  readFileSync as readFileSync5,
  readdirSync,
  statSync as statSync2
} from "node:fs";
import { homedir as homedir4 } from "node:os";
import { join as join6, relative } from "node:path";
var RULE_EXTENSIONS = /* @__PURE__ */ new Set([".md", ".mdc"]);
function readUserCursorRules(root = join6(homedir4(), ".cursor", "rules")) {
  if (!existsSync6(root)) return { text: "", count: 0, bytes: 0 };
  const paths = collectRulePaths(root).sort((a, b) => a.localeCompare(b));
  const sections = [];
  let bytes = 0;
  for (const path of paths) {
    const content = readFileSync5(path, "utf8");
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
    const path = join6(root, entry.name);
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
import { readFileSync as readFileSync6 } from "node:fs";
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
    `\u7528\u6237 Rule \u6CE8\u5165\uFF1A${userRules.count} \u4E2A\uFF0C${userRules.bytes} bytes\uFF1B\u4E0D\u52A0\u8F7D\u7528\u6237 Skill`
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
      const roundLabel = limit >= 999 ? `${index}` : `${index}/${limit}`;
      workerLog(`\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500 Worker \u5355\u5361\u8F6E\u6B21 ${roundLabel} \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500`);
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
        if (JSON.stringify(tools) !== JSON.stringify(SCOPED_TOOL_NAMES)) {
          throw new Error(
            `scoped MCP \u5DE5\u5177\u95E8\u7981\u5931\u8D25\uFF1A\u5B9E\u9645=${tools.join(",")}\uFF0C\u671F\u671B=${SCOPED_TOOL_NAMES.join(",")}`
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
            projectMcpTags: parseProjectMcpTags(claim.payload)
          }
        };
        logModelOverride(liveJob, roundJob, cardId);
        logClaimedCard(claim.payload);
        workerLog("Worker \u6B63\u5728\u5B9E\u65BD\u5F53\u524D\u5361\u7247");
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
        const pending = asRecord4(status.pending);
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
    const record = asRecord4(raw);
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
function asRecord4(value) {
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
    const record = asRecord4(raw);
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
    const raw = JSON.parse(readFileSync6(job.liveFile, "utf8"));
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
  writeFileSync4(outPath, JSON.stringify(result, null, 2), "utf8");
}
function withContextParameter(parameters) {
  if (parameters.some((item) => isContextParamId(item.id))) return parameters;
  return [...parameters, contextCatalogParameter()];
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
      parameters: withContextParameter(
        (m.parameters ?? []).map((p) => ({
          id: p.id,
          displayName: p.displayName,
          values: normalizeModelParameterValues(
            p.values ?? p.enum
          )
        }))
      ),
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
  const job = JSON.parse(readFileSync7(jobPath, "utf8"));
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
