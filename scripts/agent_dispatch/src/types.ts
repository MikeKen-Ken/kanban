export type EffortWire = "default" | "fast" | "low" | "medium" | "high";

export interface DispatchJob {
  engine: "cursor" | "codex";
  cwd: string;
  prompt: string;
  model?: string;
  effort?: EffortWire;
  outPath: string;
}

export interface DispatchResult {
  ok: boolean;
  summary?: string;
  error?: string;
}

export function effortToCursorParams(
  effort: EffortWire | undefined,
): Array<{ id: string; value: string }> | undefined {
  switch (effort) {
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

export function effortToCodexConfigArgs(
  effort: EffortWire | undefined,
): string[] {
  switch (effort) {
    case "low":
      return ["-c", "model_reasoning_effort=low"];
    case "medium":
      return ["-c", "model_reasoning_effort=medium"];
    case "high":
      return ["-c", "model_reasoning_effort=high"];
    case "fast":
      return ["-c", "model_reasoning_effort=low"];
    default:
      return [];
  }
}
