import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { runCodex } from "./run_codex.js";
import { runCursor } from "./run_cursor.js";
import type { DispatchJob, DispatchResult } from "./types.js";

function parseArgs(argv: string[]): { jobPath: string } {
  const idx = argv.indexOf("--job");
  if (idx < 0 || !argv[idx + 1]) {
    throw new Error("用法: node cli.js --job <job.json>");
  }
  return { jobPath: resolve(argv[idx + 1]!) };
}

function writeResult(outPath: string, result: DispatchResult): void {
  writeFileSync(outPath, JSON.stringify(result, null, 2), "utf8");
}

async function main(): Promise<void> {
  const { jobPath } = parseArgs(process.argv.slice(2));
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
    if (job.engine === "codex") {
      result = await runCodex(job);
    } else {
      result = await runCursor(job);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    result = { ok: false, error: message };
  }

  writeResult(job.outPath, result);
  process.exitCode = result.ok ? 0 : 2;
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
