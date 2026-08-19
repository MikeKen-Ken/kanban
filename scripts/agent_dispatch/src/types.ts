export type ModelParam = { id: string; value: string };

export type EngineDefault = {
  model?: string;
  modelParams?: ModelParam[];
  models?: Array<{
    id: string;
    parameters?: Array<{ id: string; values?: string[] }>;
  }>;
};

export type DispatchJob = {
  engine: "cursor" | "codex";
  cwd: string;
  prompt: string;
  model?: string;
  modelParams?: ModelParam[];
  engineDefaults?: Partial<Record<"cursor" | "codex", EngineDefault>>;
  mcpEndpoint: string;
  projectId?: string;
  cardLimit: number;
  workerToken: string;
  /** 为 true 时忽略卡片上的引擎 / 模型 / 参数 / 脏工作区 / 沙箱开关，只用工作台默认。 */
  ignoreCardParams?: boolean;
  /** 为 true 时工作区有未提交改动仍可领取；默认 false。 */
  allowDirtyWorkspace?: boolean;
  /** 为 true 时开启 Cursor SDK 沙箱；默认 false。 */
  enableSandbox?: boolean;
  /** @deprecated 旧字段，兼容 */
  effort?: string;
  /** Dart 侧 touch 此文件以请求立即停止 */
  cancelFile?: string;
  /** Dart 侧 touch 此文件以在当前 Skill 会话结束后停止批次 */
  drainFile?: string;
  /** Dart 侧 touch 此文件以跳过当前卡片并继续下一张 */
  skipFile?: string;
  /** 运行中覆盖默认平台 / 模型 / 参数；Worker 每轮领卡前重读。 */
  liveFile?: string;
  /** App 与当前 Agent 问答使用的临时目录。 */
  interactionDir?: string;
  outPath: string;
};

export function applyLiveJobOverlay(
  job: DispatchJob,
  live: Partial<DispatchJob> | null | undefined,
): DispatchJob {
  if (!live) return job;
  return {
    ...job,
    engine: parseEngine(live.engine, job.engine),
    model: typeof live.model === "string" ? live.model : job.model,
    modelParams: Array.isArray(live.modelParams)
      ? live.modelParams
      : job.modelParams,
    engineDefaults: live.engineDefaults ?? job.engineDefaults,
    ignoreCardParams: typeof live.ignoreCardParams === "boolean"
      ? live.ignoreCardParams
      : job.ignoreCardParams,
    allowDirtyWorkspace: typeof live.allowDirtyWorkspace === "boolean"
      ? live.allowDirtyWorkspace
      : job.allowDirtyWorkspace,
    enableSandbox: typeof live.enableSandbox === "boolean"
      ? live.enableSandbox
      : job.enableSandbox,
  };
}

export type RoundImage = {
  data: string;
  mimeType: string;
};

export type RoundContext = {
  cardId: string;
  sessionId: string;
  agentEndpointUrl: string;
  images: RoundImage[];
  attachmentPaths: string[];
  /** 冻结的卡片上下文，用于生成用户可读的会话记录。 */
  cardContext?: Record<string, unknown>;
  /** 项目级 MCP 标签 key，用于按需注入用户 MCP；无标签时只挂 scoped 看板 MCP。 */
  projectMcpTags: string[];
  /** Worker 把 Shell 起止报到完整 MCP，供 ready_to_submit 拒绝未完成测试。 */
  reportShellSpan?: (span: {
    callId: string;
    command: string;
    phase: "start" | "end";
    startedAtMs: number;
    endedAtMs?: number;
    executionTimeMs?: number;
    exitCode?: number;
  }) => Promise<void>;
};

export type RoundDispatchJob = DispatchJob & {
  prompt: string;
  round: RoundContext;
};

export type DispatchResult = {
  ok: boolean;
  summary?: string;
  error?: string;
  /** 仅表示暂时性网络或服务故障，Worker 可安全地有限次数重试当前卡片。 */
  retryable?: boolean;
  processedCards?: number;
  /** 为 true 时不要把 pending 标成 failed，供清理工作区后恢复。 */
  preservePending?: boolean;
};

export function isReasoningParamId(id: string): boolean {
  return (
    id === "reasoning" ||
    id === "reasoning_effort" ||
    id === "model_reasoning_effort" ||
    id === "effort" ||
    id === "thinking"
  );
}

export function conservativeParamValue(
  id: string,
  values: string[],
): string | undefined {
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
  return allowed.length === 0 ? undefined : middle;
}

function parseEngine(
  raw: unknown,
  fallback: "cursor" | "codex",
): "cursor" | "codex" {
  const text = String(raw ?? "").trim();
  return text === "cursor" || text === "codex" ? text : fallback;
}

function parseCardParams(raw: unknown): ModelParam[] {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
  return Object.entries(raw as Record<string, unknown>)
    .filter(([, value]) => typeof value === "string" && value.trim() !== "")
    .map(([id, value]) => ({ id, value: String(value).trim() }));
}

function parameterValueList(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    if (typeof item === "string" && item.trim()) return [item.trim()];
    if (item && typeof item === "object" && "value" in item) {
      const text = String((item as { value?: unknown }).value ?? "").trim();
      return text ? [text] : [];
    }
    return [];
  });
}

function engineFallback(
  job: DispatchJob,
  engine: "cursor" | "codex",
): EngineDefault {
  const stored = job.engineDefaults?.[engine];
  if (stored) return stored;
  if (engine === job.engine) {
    return { model: job.model, modelParams: job.modelParams };
  }
  return {};
}

export function mergeJobWithCardOverrides(
  job: DispatchJob,
  claim: Record<string, unknown>,
): DispatchJob {
  if (job.ignoreCardParams === true) return job;

  const engine = parseEngine(claim.agentEngine, job.engine);
  const defaults = engineFallback(job, engine);
  const cardModel = String(claim.agentModelId ?? "").trim();
  const model = cardModel || defaults.model || undefined;
  const cardParams = parseCardParams(claim.agentModelParamValues);
  const byId = new Map(
    (defaults.modelParams ?? []).map((item) => [item.id, item]),
  );
  for (const item of cardParams) byId.set(item.id, item);

  const catalog = defaults.models?.find((item) => item.id === model);
  const rawParameters = catalog?.parameters ?? [];
  const parameters = ensureContextParameter(rawParameters);
  // Cursor SDK 只接受 models.list 里的参数；`context` 是看板自己补的，传上去会报不支持。
  const fillFrom = engine === "cursor" ? rawParameters : parameters;
  if (rawParameters.length > 0) {
    const allowed = new Set(
      fillFrom.map((item) => String(item.id ?? "").trim()).filter(Boolean),
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
    allowDirtyWorkspace: job.allowDirtyWorkspace === true ||
      isTrueFlag(claim.agentAllowDirtyWorkspace),
    enableSandbox: job.enableSandbox === true ||
      isTrueFlag(claim.agentEnableSandbox),
  };
}

function isTrueFlag(raw: unknown): boolean {
  if (raw === true) return true;
  if (typeof raw !== "string") return false;
  return raw.trim().toLowerCase() === "true";
}

export function isContextParamId(id: string): boolean {
  return id.toLowerCase().includes("context");
}

export const DEFAULT_CONTEXT_VALUES = ["64k", "272k"] as const;

type CatalogParameter = {
  id: string;
  displayName?: string;
  values?: string[];
};

export function contextCatalogParameter(): {
  id: string;
  displayName: string;
  values: Array<{ value: string; displayName: string }>;
} {
  return {
    id: "context",
    displayName: "上下文",
    values: DEFAULT_CONTEXT_VALUES.map((value) => ({
      value,
      displayName: value,
    })),
  };
}

export function ensureContextParameter<T extends CatalogParameter>(
  parameters: T[],
): T[] {
  if (parameters.some((item) => isContextParamId(String(item.id ?? "")))) {
    return parameters;
  }
  return [
    ...parameters,
    {
      id: "context",
      displayName: "上下文",
      values: [...DEFAULT_CONTEXT_VALUES],
    } as T,
  ];
}

export function parseTokenBudget(value: string): number | undefined {
  const match = /^(\d+(?:\.\d+)?)\s*(k|m|kb|mb)?$/i.exec(value.trim());
  if (!match) return undefined;
  const amount = Number(match[1]);
  if (!Number.isFinite(amount)) return undefined;
  const unit = (match[2] ?? "").toLowerCase();
  if (unit === "m" || unit === "mb") return amount * 1_000_000;
  if (unit === "k" || unit === "kb") return amount * 1_000;
  return amount;
}

export function resolveModelParams(
  job: DispatchJob,
): Array<{ id: string; value: string }> | undefined {
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
      return undefined;
  }
}

function cursorCatalogParameterIds(job: DispatchJob): string[] {
  const modelId = job.model?.trim() || "composer-2.5";
  const catalog = job.engineDefaults?.cursor?.models?.find(
    (item) => item.id === modelId,
  );
  return (catalog?.parameters ?? [])
    .map((item) => String(item.id ?? "").trim())
    .filter((id) => id.length > 0 && !isContextParamId(id));
}

/** Composer 系列才有 fast；无目录时不要把 fast 传给 Grok 等模型。 */
export function cursorModelLikelySupportsFast(modelId: string): boolean {
  return /composer/i.test(modelId.trim());
}

export function withCursorSdkCatalog(
  job: DispatchJob,
  models: NonNullable<EngineDefault["models"]> | undefined,
): DispatchJob {
  if (!models || models.length === 0) return job;
  return {
    ...job,
    engineDefaults: {
      ...job.engineDefaults,
      cursor: {
        ...job.engineDefaults?.cursor,
        models,
      },
    },
  };
}

function errorLooksLikeUnsupportedParam(text: string): boolean {
  return /not supported|unsupported|unknown param|invalid param|unrecognized param/i.test(
    text,
  );
}

/** Agent.create 因参数不支持失败时，丢掉被点名的项；未点名则去掉全部 params 再试。 */
export function nextCursorSdkParamsAfterCreateError(
  params: ModelParam[] | undefined,
  err: unknown,
): { changed: boolean; params?: ModelParam[]; dropped: string[] } {
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
    params: kept.length > 0 ? kept : undefined,
    dropped: [...new Set(dropped)],
  };
}

/** Cursor Agent.create 只应收到官方 catalog 参数；丢掉 context 等自造项。 */
export function selectCursorSdkModelParams(job: DispatchJob): {
  params?: ModelParam[];
  dropped: string[];
} {
  const raw = resolveModelParams(job) ?? [];
  const modelId = job.model?.trim() || "composer-2.5";
  const catalogIds = cursorCatalogParameterIds(job);
  const allowed = new Set(catalogIds);
  const hasFast = raw.some((item) => item.id === "fast");
  const dropped: string[] = [];
  const kept: ModelParam[] = [];
  for (const item of raw) {
    if (isContextParamId(item.id)) {
      dropped.push(item.id);
      continue;
    }
    if (allowed.size > 0 && !allowed.has(item.id)) {
      dropped.push(item.id);
      continue;
    }
    if (
      allowed.size === 0 &&
      item.id === "fast" &&
      !cursorModelLikelySupportsFast(modelId)
    ) {
      dropped.push(item.id);
      continue;
    }
    if (
      allowed.size === 0 &&
      hasFast &&
      isReasoningParamId(item.id) &&
      cursorModelLikelySupportsFast(modelId)
    ) {
      dropped.push(item.id);
      continue;
    }
    kept.push(item);
  }
  return {
    params: kept.length > 0 ? kept : undefined,
    dropped: [...new Set(dropped)],
  };
}

export function effortToCodexConfigArgs(job: DispatchJob): string[] {
  const params = resolveModelParams(job) ?? [];
  const args: string[] = [];
  const effort = params.find(
    (p) => p.id === "reasoning_effort" || p.id === "model_reasoning_effort",
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
