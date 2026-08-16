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
  /** 工作台默认：为 true 时不改卡片/面板的推理、Fast、上下文；卡片可再覆盖。 */
  allowHighReasoning?: boolean;
  /** @deprecated 旧字段，兼容 */
  effort?: string;
  /** Dart 侧 touch 此文件以请求立即停止 */
  cancelFile?: string;
  /** Dart 侧 touch 此文件以在当前 Skill 会话结束后停止批次 */
  drainFile?: string;
  /** Dart 侧 touch 此文件以跳过当前卡片并继续下一张 */
  skipFile?: string;
  outPath: string;
};

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
};

export type RoundDispatchJob = DispatchJob & {
  prompt: string;
  round: RoundContext;
};

export type DispatchResult = {
  ok: boolean;
  summary?: string;
  error?: string;
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
  const engine = parseEngine(claim.agentEngine, job.engine);
  const defaults = engineFallback(job, engine);
  const cardModel = String(claim.agentModelId ?? "").trim();
  const model = cardModel || defaults.model || undefined;
  const cardParams = parseCardParams(claim.agentModelParamValues);
  const byId = new Map(
    (defaults.modelParams ?? []).map((item) => [item.id, item]),
  );
  for (const item of cardParams) byId.set(item.id, item);
  const allowHighReasoning = resolveAllowHighReasoning(job, claim);

  const catalog = defaults.models?.find((item) => item.id === model);
  const rawParameters = catalog?.parameters ?? [];
  const parameters = ensureContextParameter(rawParameters);
  if (rawParameters.length > 0) {
    const allowed = new Set(
      parameters.map((item) => String(item.id ?? "").trim()).filter(Boolean),
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

  const modelParams = [...byId.values()].map((item) => ({
    ...item,
    value: clampUnattendedParam(item, allowHighReasoning),
  }));
  return { ...job, engine, model, modelParams, allowHighReasoning };
}

export function resolveAllowHighReasoning(
  job: DispatchJob,
  claim: Record<string, unknown>,
): boolean {
  const card = parseOptionalBool(claim.agentAllowHighReasoning);
  if (card != null) return card;
  return job.allowHighReasoning === true;
}

function parseOptionalBool(raw: unknown): boolean | undefined {
  if (raw === true || raw === false) return raw;
  if (typeof raw !== "string") return undefined;
  const text = raw.trim().toLowerCase();
  if (text === "true") return true;
  if (text === "false") return false;
  return undefined;
}

export function clampUnattendedParam(
  param: ModelParam,
  allowHighReasoning: boolean,
): string {
  if (allowHighReasoning) return param.value;
  const id = param.id.toLowerCase();
  const value = param.value.toLowerCase();
  if (isContextParamId(id)) {
    const tokens = parseTokenBudget(value);
    if (tokens != null && tokens > MAX_UNATTENDED_CONTEXT_TOKENS) {
      return "64k";
    }
  }
  const expensive = new Set([
    "high",
    "xhigh",
    "extra_high",
    "very_high",
    "max",
    "maximum",
    "large",
    "xlarge",
    "huge",
  ]);
  if (
    expensive.has(value) &&
    (isReasoningParamId(id) ||
      isContextParamId(id) ||
      id.includes("thinking"))
  ) {
    return "medium";
  }
  return param.value;
}

export function isContextParamId(id: string): boolean {
  return id.toLowerCase().includes("context");
}

export const MAX_UNATTENDED_CONTEXT_TOKENS = 64_000;

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
    return job.modelParams.map((item) => ({
      ...item,
      value: clampUnattendedParam(item, job.allowHighReasoning === true),
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
        value: job.allowHighReasoning === true ? "high" : "medium",
      }];
    default:
      return undefined;
  }
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
