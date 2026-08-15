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
  /** Skill 会话使用的精简 MCP；缺省则回退 mcpEndpoint。 */
  agentMcpEndpoint?: string;
  projectId?: string;
  cardLimit: number;
  workerToken: string;
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

export type DispatchResult = {
  ok: boolean;
  summary?: string;
  error?: string;
  processedCards?: number;
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
  peek: Record<string, unknown>,
): DispatchJob {
  const engine = parseEngine(peek.agentEngine, job.engine);
  const defaults = engineFallback(job, engine);
  const cardModel = String(peek.agentModelId ?? "").trim();
  const model = cardModel || defaults.model || undefined;
  const cardParams = parseCardParams(peek.agentModelParamValues);
  const byId = new Map(
    (defaults.modelParams ?? []).map((item) => [item.id, item]),
  );
  for (const item of cardParams) byId.set(item.id, item);

  const catalog = defaults.models?.find((item) => item.id === model);
  const parameters = catalog?.parameters ?? [];
  if (parameters.length > 0) {
    const allowed = new Set(
      parameters.map((item) => String(item.id ?? "").trim()).filter(Boolean),
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

  return { ...job, engine, model, modelParams: [...byId.values()] };
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

export function effortToCodexConfigArgs(job: DispatchJob): string[] {
  const params = resolveModelParams(job) ?? [];
  const effort = params.find(
    (p) => p.id === "reasoning_effort" || p.id === "model_reasoning_effort",
  );
  if (effort) {
    return ["-c", `model_reasoning_effort=${effort.value}`];
  }
  if (params.some((p) => p.id === "fast" && p.value === "true")) {
    return ["-c", "model_reasoning_effort=low"];
  }
  return [];
}
