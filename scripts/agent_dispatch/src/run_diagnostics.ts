export type AgentRunMetrics = {
  steps: number;
  toolCalls: number;
  repeatedToolCalls: number;
  repeatedReads: number;
  topReads: string[];
};

/** 只统计模型步骤；不读取工具结果正文，避免诊断本身放大上下文。 */
export class AgentRunDiagnostics {
  private steps = 0;
  private toolCalls = 0;
  private repeatedToolCalls = 0;
  private readonly signatures = new Map<string, number>();
  private readonly reads = new Map<string, number>();

  recordStep(input: {
    type: string;
    toolName?: string;
    detail?: string;
  }): void {
    this.steps += 1;
    if (input.type !== "toolCall") return;

    this.toolCalls += 1;
    const name = input.toolName?.trim() || "tool";
    const detail = input.detail?.trim() || "";
    const signature = `${name.toLowerCase()}\u0000${detail}`;
    const seen = this.signatures.get(signature) ?? 0;
    if (seen > 0) this.repeatedToolCalls += 1;
    this.signatures.set(signature, seen + 1);

    if (name.toLowerCase() === "read") {
      const path = readPath(detail);
      if (path) this.reads.set(path, (this.reads.get(path) ?? 0) + 1);
    }
  }

  snapshot(): AgentRunMetrics {
    const repeatedReads = [...this.reads.values()].reduce(
      (sum, count) => sum + Math.max(0, count - 1),
      0,
    );
    const topReads = [...this.reads.entries()]
      .filter(([, count]) => count > 1)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 3)
      .map(([path, count]) => `${path}×${count}`);
    return {
      steps: this.steps,
      toolCalls: this.toolCalls,
      repeatedToolCalls: this.repeatedToolCalls,
      repeatedReads,
      topReads,
    };
  }
}

export function formatAgentRunDiagnostics(metrics: AgentRunMetrics): string {
  return (
    `会话诊断：steps=${metrics.steps} tools=${metrics.toolCalls}` +
    ` repeatedToolCalls=${metrics.repeatedToolCalls}` +
    ` repeatedReads=${metrics.repeatedReads}` +
    (metrics.topReads.length > 0 ? ` topReads=${metrics.topReads.join(",")}` : "")
  );
}

function readPath(detail: string): string | undefined {
  try {
    const parsed = JSON.parse(detail) as Record<string, unknown>;
    const value = parsed.path ?? parsed.filePath ?? parsed.file_path;
    if (typeof value === "string" && value.trim()) {
      return value.trim().replaceAll("\\", "/").toLowerCase();
    }
  } catch {
    // 旧版工具可能直接把路径作为参数。
  }
  const raw = detail.trim();
  return raw && !raw.startsWith("{") ? raw.replaceAll("\\", "/").toLowerCase() : undefined;
}
