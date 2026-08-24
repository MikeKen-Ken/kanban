import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { Cursor } from "@cursor/sdk";
import {
  WorkerCancelledError,
  WorkerCancellation,
} from "./cancellation.ts";
import { printCursorUsage } from "./cursor_usage.ts";
import { listCodexModels } from "./codex_models.ts";
import { withRetry } from "./retry.ts";
import { resolveCodexCommand } from "./run_codex.ts";
import { runBatch } from "./run_batch.ts";
import { type DispatchJob, type DispatchResult } from "./types.ts";

function formatListModelsError(err: unknown): string {
  if (err && typeof err === "object" && "message" in err) {
    const message = String((err as { message?: unknown }).message).trim();
    if (message) return `Cursor.models.list failed: ${message}`;
  }
  return `Cursor.models.list failed: ${String(err)}`;
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

async function listModels(engine: "cursor" | "codex"): Promise<void> {
  if (engine === "codex") {
    try {
      const models = await listCodexModels(resolveCodexCommand());
      process.stdout.write(`${JSON.stringify({ models })}\n`);
    } catch (err) {
      console.error(`Codex model/list failed: ${err instanceof Error ? err.message : String(err)}`);
      process.exitCode = 2;
    }
    return;
  }
  const apiKey = process.env.CURSOR_API_KEY?.trim();
  if (!apiKey) {
    console.error("Missing CURSOR_API_KEY");
    process.exitCode = 2;
    return;
  }
  let models;
  try {
    models = await withRetry(
      "Fetch model list",
      () => Cursor.models.list({ apiKey }),
      {
        onRetry: ({ operation, attempt, maxAttempts, delayMs }) => {
          console.error(
            `${operation} failed (attempt ${attempt}/${maxAttempts}), retrying in ${delayMs}ms…`,
          );
        },
      },
    );
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
    throw new Error("job.outPath is required");
  }
  if (!job.cwd?.trim()) {
    writeResult(job.outPath, { ok: false, error: "cwd cannot be empty" });
    process.exitCode = 2;
    return;
  }
  if (!job.prompt?.trim()) {
    writeResult(job.outPath, { ok: false, error: "prompt cannot be empty" });
    process.exitCode = 2;
    return;
  }
  if (!job.mcpEndpoint?.trim()) {
    writeResult(job.outPath, { ok: false, error: "mcpEndpoint cannot be empty" });
    process.exitCode = 2;
    return;
  }
  if (!job.workerToken?.trim()) {
    writeResult(job.outPath, { ok: false, error: "workerToken cannot be empty" });
    process.exitCode = 2;
    return;
  }
  if (!Number.isFinite(job.cardLimit) || job.cardLimit < 1) {
    writeResult(job.outPath, { ok: false, error: "cardLimit must be greater than 0" });
    process.exitCode = 2;
    return;
  }

  console.log(`engine=${job.engine} cwd=${job.cwd}`);
  const cancellation = new WorkerCancellation();
  cancellation.installSignalHandlers();
  if (job.cancelFile?.trim()) {
    cancellation.watchCancelFile(job.cancelFile.trim());
  }
  if (job.drainFile?.trim()) {
    cancellation.watchDrainFile(job.drainFile.trim());
  }
  if (job.skipFile?.trim()) {
    cancellation.watchSkipFile(job.skipFile.trim());
  }
  let result: DispatchResult;
  try {
    result = await runBatch(job, cancellation);
  } catch (err) {
    if (err instanceof WorkerCancelledError) {
      result = { ok: false, error: err.message };
    } else {
      const message = err instanceof Error ? err.message : String(err);
      result = { ok: false, error: message };
    }
  } finally {
    cancellation.dispose();
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
    const engine = argv[argv.indexOf("--list-models") + 1] === "codex"
      ? "codex"
      : "cursor";
    await listModels(engine);
    return;
  }
  if (argv.includes("--usage")) {
    await printCursorUsage();
    return;
  }
  const idx = argv.indexOf("--job");
  if (idx < 0 || !argv[idx + 1]) {
    throw new Error(
      "Usage: node cli.js --job <job.json> | --list-models | --usage",
    );
  }
  await runJob(resolve(argv[idx + 1]!));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
