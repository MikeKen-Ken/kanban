import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { Cursor } from "@cursor/sdk";
import { printCursorUsage } from "./cursor_usage.js";
import { runBatch } from "./run_batch.js";
import type { DispatchJob, DispatchResult } from "./types.js";

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableError(err: unknown): boolean {
  if (err && typeof err === "object") {
    if ("isRetryable" in err && (err as { isRetryable?: boolean }).isRetryable) {
      return true;
    }
    const message = err instanceof Error ? err.message : String(err);
    const lower = message.toLowerCase();
    if (
      lower.includes("network") ||
      lower.includes("fetch failed") ||
      lower.includes("connect timeout") ||
      lower.includes("econnreset") ||
      lower.includes("etimedout") ||
      lower.includes("und_err_connect_timeout")
    ) {
      return true;
    }
    if ("cause" in err && err.cause) {
      return isRetryableError(err.cause);
    }
  }
  return false;
}

function formatListModelsError(err: unknown): string {
  if (err && typeof err === "object" && "message" in err) {
    const message = String((err as { message?: unknown }).message).trim();
    if (message) return `Cursor.models.list 失败：${message}`;
  }
  return `Cursor.models.list 失败：${String(err)}`;
}

async function withRetry<T>(
  operation: string,
  fn: () => Promise<T>,
  options?: { maxAttempts?: number; baseDelayMs?: number },
): Promise<T> {
  const maxAttempts = options?.maxAttempts ?? 3;
  const baseDelayMs = options?.baseDelayMs ?? 1000;
  let lastError: unknown;
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
        `${operation} 失败（第 ${attempt}/${maxAttempts} 次），${delayMs}ms 后重试…`,
      );
      await sleep(delayMs);
    }
  }
  throw lastError;
}

function writeResult(outPath: string, result: DispatchResult): void {
  writeFileSync(outPath, JSON.stringify(result, null, 2), "utf8");
}

function normalizeModelParameterValues(
  input: unknown,
): Array<{ value: string; displayName?: string }> {
  if (!Array.isArray(input)) return [];
  return input
    .map((item): { value: string; displayName?: string } | null => {
      if (item && typeof item === "object" && "value" in item) {
        const value = (item as { value?: unknown }).value;
        const displayName = (item as { displayName?: unknown }).displayName;
        return value == null
          ? null
          : {
              value: String(value),
              ...(displayName == null
                ? {}
                : { displayName: String(displayName) }),
            };
      }
      return item == null ? null : { value: String(item) };
    })
    .filter(
      (item): item is { value: string; displayName?: string } =>
        item !== null && item.value.length > 0,
    );
}

async function listModels(): Promise<void> {
  const apiKey = process.env.CURSOR_API_KEY?.trim();
  if (!apiKey) {
    console.error("缺少 CURSOR_API_KEY");
    process.exitCode = 2;
    return;
  }
  let models;
  try {
    models = await withRetry("拉取模型列表", () => Cursor.models.list({ apiKey }));
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
      parameters: (m.parameters ?? []).map((p) => ({
        id: p.id,
        displayName: p.displayName,
        values: normalizeModelParameterValues(
          (p as { values?: unknown }).values ??
            (p as { enum?: unknown }).enum,
        ),
      })),
      variants: (m.variants ?? []).map((variant) => ({
        displayName: variant.displayName,
        description: variant.description,
        isDefault: variant.isDefault,
        params: variant.params,
      })),
    })),
  };
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

async function runJob(jobPath: string): Promise<void> {
  const job = JSON.parse(readFileSync(jobPath, "utf8")) as DispatchJob;
  if (!job.outPath) {
    throw new Error("job.outPath 必填");
  }
  if (!job.cwd?.trim()) {
    writeResult(job.outPath, { ok: false, error: "cwd 不能为空" });
    process.exitCode = 2;
    return;
  }
  if (!job.prompt?.trim()) {
    writeResult(job.outPath, { ok: false, error: "prompt 不能为空" });
    process.exitCode = 2;
    return;
  }
  if (!job.mcpEndpoint?.trim()) {
    writeResult(job.outPath, { ok: false, error: "mcpEndpoint 不能为空" });
    process.exitCode = 2;
    return;
  }
  if (!job.workerToken?.trim()) {
    writeResult(job.outPath, { ok: false, error: "workerToken 不能为空" });
    process.exitCode = 2;
    return;
  }
  if (!Number.isFinite(job.cardLimit) || job.cardLimit < 1) {
    writeResult(job.outPath, { ok: false, error: "cardLimit 必须大于 0" });
    process.exitCode = 2;
    return;
  }

  console.log(`engine=${job.engine} cwd=${job.cwd}`);
  let result: DispatchResult;
  try {
    result = await runBatch(job);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    result = { ok: false, error: message };
  }

  writeResult(job.outPath, result);
  const code = result.ok ? 0 : 2;
  process.exitCode = code;
  // Cursor 本地运行时 / MCP SSE 可能留下未关闭句柄，仅设 exitCode 不会退出。
  process.exit(code);
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  if (argv.includes("--list-models")) {
    await listModels();
    return;
  }
  if (argv.includes("--usage")) {
    await printCursorUsage();
    return;
  }
  const idx = argv.indexOf("--job");
  if (idx < 0 || !argv[idx + 1]) {
    throw new Error(
      "用法: node cli.js --job <job.json> | --list-models | --usage",
    );
  }
  await runJob(resolve(argv[idx + 1]!));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
