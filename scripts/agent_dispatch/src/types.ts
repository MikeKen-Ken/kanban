export type DispatchJob = {
  engine: "cursor" | "codex";
  cwd: string;
  prompt: string;
  model?: string;
  modelParams?: Array<{ id: string; value: string }>;
  mcpEndpoint: string;
  projectId?: string;
  cardLimit: number;
  workerToken: string;
  /** @deprecated 旧字段，兼容 */
  effort?: string;
  /** Dart 侧 touch 此文件以请求立即停止 */
  cancelFile?: string;
  /** Dart 侧 touch 此文件以在当前 Skill 会话结束后停止批次 */
  drainFile?: string;
  outPath: string;
};

export type DispatchResult = {
  ok: boolean;
  summary?: string;
  error?: string;
  processedCards?: number;
};

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
