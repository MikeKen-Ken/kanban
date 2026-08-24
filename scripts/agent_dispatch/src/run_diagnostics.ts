export type AgentRunMetrics = {
  steps: number;
  toolCalls: number;
  repeatedToolCalls: number;
  repeatedReads: number;
  topReads: string[];
};

/** \u53EA\u7EDF\u8BA1\u6A21\u578B\u6B65\u9AA4；\u4E0D\u8BFB\u53D6\u5DE5\u5177\u7ED3\u679C\u6B63\u6587，\u907F\u514D\u8BCA\u65AD\u672C\u8EAB\u653E\u5927\u4E0A\u4E0B\u6587。 */
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
    `Session diagnostics: steps=${metrics.steps} tools=${metrics.toolCalls}` +
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
    // \u65E7\u7248\u5DE5\u5177\u53EF\u80FD\u76F4\u63A5\u628A\u8DEF\u5F84\u4F5C\u4E3A\u53C2\u6570。
  }
  const raw = detail.trim();
  return raw && !raw.startsWith("{") ? raw.replaceAll("\\", "/").toLowerCase() : undefined;
}
