import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface } from "node:readline";
import { contextCatalogParameter, isContextParamId } from "./types.ts";

type JsonRpcResponse = {
  id?: number;
  result?: unknown;
  error?: { message?: string };
};

type CodexModel = {
  id?: string;
  model?: string;
  displayName?: string;
  description?: string;
  defaultReasoningEffort?: string;
  supportedReasoningEfforts?: Array<{
    reasoningEffort?: string;
    description?: string;
  }>;
};

type CodexModelListResult = {
  data?: CodexModel[];
  nextCursor?: string | null;
};

export type CodexModelCatalogItem = {
  id: string;
  displayName?: string;
  description?: string;
  parameters: Array<{
    id: string;
    displayName: string;
    values: Array<{ value: string; displayName: string }>;
  }>;
  variants: Array<{
    displayName: string;
    description?: string;
    isDefault: boolean;
    params: Array<{ id: string; value: string }>;
  }>;
};

type CodexCommand = {
  command: string;
  prefixArgs: string[];
  shell: boolean;
};

export async function listCodexModels(
  codex: CodexCommand,
): Promise<CodexModelCatalogItem[]> {
  const child = spawn(
    codex.command,
    [...codex.prefixArgs, "app-server", "--stdio"],
    { stdio: ["pipe", "pipe", "pipe"], shell: codex.shell },
  );
  const stderr: string[] = [];
  child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk.toString("utf8")));

  try {
    const client = new AppServerClient(child);
    await client.request("initialize", {
      clientInfo: { name: "kanban-agent-dispatch", version: "1.0.0" },
      capabilities: { experimentalApi: false },
    });
    client.notify("initialized", {});

    const models: CodexModel[] = [];
    let cursor: string | null | undefined;
    do {
      const result = (await client.request("model/list", {
        cursor: cursor ?? null,
        includeHidden: false,
      })) as CodexModelListResult;
      models.push(...(result.data ?? []));
      cursor = result.nextCursor;
    } while (cursor);

    return models.map(toCatalogItem).filter((model) => model.id.length > 0);
  } catch (error) {
    const detail = stderr.join("").trim();
    throw new Error(detail ? `${String(error)}\n${detail}` : String(error));
  } finally {
    child.kill();
  }
}

function toCatalogItem(model: CodexModel): CodexModelCatalogItem {
  const id = (model.model ?? model.id ?? "").trim();
  const efforts = (model.supportedReasoningEfforts ?? [])
    .map((option) => ({
      value: option.reasoningEffort?.trim() ?? "",
      displayName: effortLabel(option.reasoningEffort ?? ""),
    }))
    .filter((option) => option.value.length > 0);
  const defaultEffort = model.defaultReasoningEffort?.trim();
  const effortParameter = efforts.length === 0
    ? []
    : [{
        id: "model_reasoning_effort",
        displayName: "推理程度",
        values: efforts,
      }];
  return {
    id,
    displayName: model.displayName,
    description: model.description,
    parameters: [
      ...effortParameter,
      ...(effortParameter.some((item) => isContextParamId(item.id))
        ? []
        : [contextCatalogParameter()]),
    ],
    variants: defaultEffort
      ? [{
          displayName: `默认（${effortLabel(defaultEffort)}）`,
          isDefault: true,
          params: [{ id: "model_reasoning_effort", value: defaultEffort }],
        }]
      : [],
  };
}

function effortLabel(value: string): string {
  const labels: Record<string, string> = {
    minimal: "Minimal",
    none: "None",
    low: "Low",
    medium: "Medium",
    high: "High",
    xhigh: "XHigh",
    max: "Max",
  };
  return labels[value] ?? value;
}

class AppServerClient {
  private nextId = 1;
  private readonly pending = new Map<
    number,
    { resolve: (value: unknown) => void; reject: (error: Error) => void }
  >();

  constructor(private readonly child: ChildProcessWithoutNullStreams) {
    const lines = createInterface({ input: child.stdout });
    lines.on("line", (line) => this.handleLine(line));
    child.on("error", (error) => this.rejectAll(error));
    child.on("close", (code) => {
      if (this.pending.size > 0) {
        this.rejectAll(new Error(`Codex app-server 已退出（${code ?? 1}）`));
      }
    });
  }

  request(method: string, params: unknown): Promise<unknown> {
    const id = this.nextId++;
    const promise = new Promise<unknown>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} 请求超时`));
      }, 15_000);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timeout);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timeout);
          reject(error);
        },
      });
    });
    this.write({ id, method, params });
    return promise;
  }

  notify(method: string, params: unknown): void {
    this.write({ method, params });
  }

  private write(message: unknown): void {
    this.child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  private handleLine(line: string): void {
    let response: JsonRpcResponse;
    try {
      response = JSON.parse(line) as JsonRpcResponse;
    } catch {
      return;
    }
    if (typeof response.id !== "number") return;
    const pending = this.pending.get(response.id);
    if (!pending) return;
    this.pending.delete(response.id);
    if (response.error) {
      pending.reject(new Error(response.error.message ?? "Codex app-server 请求失败"));
    } else {
      pending.resolve(response.result);
    }
  }

  private rejectAll(error: Error): void {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
}
