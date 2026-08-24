import {
  formatVerificationFailure,
  isSkippedVerificationOutput,
  summarizeCommand,
  type VerificationCommand,
  type VerificationResult,
} from "./verification_runner.ts";
import { workerLog } from "./worker_log.ts";

const LOG_OUTPUT_CHARS = 4_000;

/** Log the command plan before execution so verification has actionable context. */
export function logVerificationPlan(commands: VerificationCommand[]): void {
  workerLog(`Starting Worker validation: ${commands.length} command(s)`);
  for (let index = 0; index < commands.length; index += 1) {
    const command = commands[index]!;
    workerLog(
      `Validation command ${index + 1}/${commands.length}: ` +
        `${summarizeCommand(command.executable, command.args)} ` +
        `cwd=${command.cwd?.trim() || "."}`,
    );
  }
}

/** Log each result before recording it in Kanban so MCP failures retain the real cause. */
export function logVerificationResults(results: VerificationResult[]): void {
  for (let index = 0; index < results.length; index += 1) {
    const result = results[index]!;
    const ordinal = `${index + 1}/${results.length}`;
    if (isSkippedVerificationOutput(result.output)) {
      workerLog(
        `Validation skipped ${ordinal}: ${result.commandSummary} (not run because a previous validation failed)`,
        "worker",
        "warning",
      );
      continue;
    }
    if (result.passed) {
      workerLog(
        `Validation passed ${ordinal}: ${result.commandSummary} duration=${result.durationMs}ms`,
        "worker",
        "success",
      );
      continue;
    }
    workerLog(
      `Validation failed ${ordinal}: ${formatVerificationFailure(result)} duration=${result.durationMs}ms`,
      "worker",
      "error",
    );
    const output = result.output.trim();
    if (!output) {
      workerLog("Validation produced no output (the process may not have started)", "shell", "warning");
      continue;
    }
    workerLog(truncateLogOutput(output), "shell", "error");
  }
}

export function truncateLogOutput(output: string): string {
  if (output.length <= LOG_OUTPUT_CHARS) return output;
  return `${output.slice(0, LOG_OUTPUT_CHARS)}\n...(log truncated; full output is stored in the validation result)`;
}
