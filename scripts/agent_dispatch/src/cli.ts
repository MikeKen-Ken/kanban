import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { Cursor } from "@cursor/sdk";
import { runCodex } from "./run_codex.js";
import { runCursor } from "./run_cursor.js";
import type { DispatchJob, DispatchResult } from "./types.js";

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
  const models = await Cursor.models.list({ apiKey });
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

  console.log(`engine=${job.engine} cwd=${job.cwd}`);
  let result: DispatchResult;
  try {
    result = job.engine === "codex" ? await runCodex(job) : await runCursor(job);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    result = { ok: false, error: message };
  }

  writeResult(job.outPath, result);
  process.exitCode = result.ok ? 0 : 2;
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  if (argv.includes("--list-models")) {
    await listModels();
    return;
  }
  const idx = argv.indexOf("--job");
  if (idx < 0 || !argv[idx + 1]) {
    throw new Error("用法: node cli.js --job <job.json> | --list-models");
  }
  await runJob(resolve(argv[idx + 1]!));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
