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
  /** \u4E3A true \u65F6\u5FFD\u7565\u5361\u7247\u4E0A\u7684\u5F15\u64CE / \u6A21\u578B / \u53C2\u6570 / \u810F\u5DE5\u4F5C\u533A / \u6C99\u7BB1 / \u6D4B\u8BD5\u5F00\u5173，\u53EA\u7528\u5DE5\u4F5C\u53F0\u9ED8\u8BA4。 */
  ignoreCardParams?: boolean;
  /** \u4E3A true \u65F6\u5DE5\u4F5C\u533A\u6709\u672A\u63D0\u4EA4\u6539\u52A8\u4ECD\u53EF\u9886\u53D6；\u9ED8\u8BA4 false。 */
  allowDirtyWorkspace?: boolean;
  /** \u4E3A true \u65F6\u5F00\u542F Cursor SDK \u6C99\u7BB1；\u9ED8\u8BA4 false。 */
  enableSandbox?: boolean;
  /** \u4E3A false \u65F6，\u672C\u5361\u4E0D\u8981\u6C42\u6267\u884C\u81EA\u52A8\u5316\u6D4B\u8BD5；\u7F3A\u7701\u4E3A true。 */
  requireTests?: boolean;
  /** \u4E3A true \u65F6\u6536\u5C3E\u5DE5\u5177\u6210\u529F\u843D\u76D8\u540E\u4E3B\u52A8\u7ED3\u675F Agent \u4F1A\u8BDD；\u9ED8\u8BA4 true。 */
  terminateAfterDispatchTerminal?: boolean;
  /** @deprecated \u65E7\u5B57\u6BB5，\u517C\u5BB9 */
  effort?: string;
  /** Dart \u4FA7 touch \u6B64\u6587\u4EF6\u4EE5\u8BF7\u6C42\u7ACB\u5373\u505C\u6B62 */
  cancelFile?: string;
  /** Dart \u4FA7 touch \u6B64\u6587\u4EF6\u4EE5\u5728\u5F53\u524D Skill \u4F1A\u8BDD\u7ED3\u675F\u540E\u505C\u6B62\u6279\u6B21 */
  drainFile?: string;
  /** Dart \u4FA7 touch \u6B64\u6587\u4EF6\u4EE5\u8DF3\u8FC7\u5F53\u524D\u5361\u7247\u5E76\u7EE7\u7EED\u4E0B\u4E00\u5F20 */
  skipFile?: string;
  /** \u8FD0\u884C\u4E2D\u8986\u76D6\u9ED8\u8BA4\u5E73\u53F0 / \u6A21\u578B / \u53C2\u6570；Worker \u6BCF\u8F6E\u9886\u5361\u524D\u91CD\u8BFB。 */
  liveFile?: string;
  /** App \u4E0E\u5F53\u524D Agent \u95EE\u7B54\u4F7F\u7528\u7684\u4E34\u65F6\u76EE\u5F55。 */
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
    requireTests: typeof live.requireTests === "boolean"
      ? live.requireTests
      : job.requireTests,
    terminateAfterDispatchTerminal:
      typeof live.terminateAfterDispatchTerminal === "boolean"
        ? live.terminateAfterDispatchTerminal
        : job.terminateAfterDispatchTerminal,
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
  /** \u51BB\u7ED3\u7684\u5361\u7247\u4E0A\u4E0B\u6587，\u7528\u4E8E\u751F\u6210\u7528\u6237\u53EF\u8BFB\u7684\u4F1A\u8BDD\u8BB0\u5F55。 */
  cardContext?: Record<string, unknown>;
  /** \u9879\u76EE\u7EA7 MCP \u6807\u7B7E key，\u7528\u4E8E\u6309\u9700\u6CE8\u5165\u7528\u6237 MCP；\u65E0\u6807\u7B7E\u65F6\u53EA\u6302 scoped \u770B\u677F MCP。 */
  projectMcpTags: string[];
  /** Worker \u628A Shell \u8D77\u6B62\u62A5\u5230\u5B8C\u6574 MCP，\u4F9B ready_to_submit \u62D2\u7EDD\u672A\u5B8C\u6210\u6D4B\u8BD5。 */
  reportShellSpan?: (span: {
    callId: string;
    command: string;
    phase: "start" | "end";
    startedAtMs: number;
    endedAtMs?: number;
    executionTimeMs?: number;
    exitCode?: number;
  }) => Promise<void>;
  /**
   * \u6536\u5C3E\u5DE5\u5177\u5DF2\u5728 MCP \u843D\u76D8\u540E\u7684\u4F1A\u8BDD\u72B6\u6001。Worker \u7528\u6765\u7ED3\u675F SDK run，
   * \u907F\u514D ready_to_submit \u6210\u529F\u540E\u6A21\u578B\u7EE7\u7EED\u641C\u6539。
   */
  peekDispatchTerminal?: () => Promise<
    "none" | "declared" | "verify" | "blocked"
  >;
};

export type RoundDispatchJob = DispatchJob & {
  prompt: string;
  round: RoundContext;
};

export type DispatchResult = {
  ok: boolean;
  summary?: string;
  error?: string;
  /** \u4EC5\u8868\u793A\u6682\u65F6\u6027\u7F51\u7EDC\u6216\u670D\u52A1\u6545\u969C，Worker \u53EF\u5B89\u5168\u5730\u6709\u9650\u6B21\u6570\u91CD\u8BD5\u5F53\u524D\u5361\u7247。 */
  retryable?: boolean;
  processedCards?: number;
  /** \u4E3A true \u65F6\u4E0D\u8981\u628A pending \u6807\u6210 failed，\u4F9B\u6E05\u7406\u5DE5\u4F5C\u533A\u540E\u6062\u590D。 */
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
  // Cursor SDK \u53EA\u63A5\u53D7 models.list \u91CC\u7684\u53C2\u6570；`context` \u662F\u770B\u677F\u81EA\u5DF1\u8865\u7684，\u4F20\u4E0A\u53BB\u4F1A\u62A5\u4E0D\u652F\u6301。
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
      // Context is opt-in. Omitting it means API default, not a conservative 64k cap.
      if (!id || byId.has(id) || isContextParamId(id)) continue;
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
    requireTests: claim.agentRequireTests === false
      ? false
      : isTrueFlag(claim.agentRequireTests)
        ? true
        : job.requireTests,
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
    displayName: "Context",
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
      displayName: "Context",
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

/** Composer \u7CFB\u5217\u624D\u6709 fast；\u65E0\u76EE\u5F55\u65F6\u4E0D\u8981\u628A fast \u4F20\u7ED9 Grok \u7B49\u6A21\u578B。 */
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

/** Agent.create \u56E0\u53C2\u6570\u4E0D\u652F\u6301\u5931\u8D25\u65F6，\u4E22\u6389\u88AB\u70B9\u540D\u7684\u9879；\u672A\u70B9\u540D\u5219\u53BB\u6389\u5168\u90E8 params \u518D\u8BD5。 */
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

/** Cursor Agent.create \u53EA\u5E94\u6536\u5230\u5B98\u65B9 catalog \u53C2\u6570；\u4E22\u6389 context \u7B49\u81EA\u9020\u9879。 */
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
