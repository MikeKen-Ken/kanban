import {
  formatVerificationFailure,
  summarizeCommand,
  type VerificationCommand,
  type VerificationResult,
} from "./verification_runner.ts";
import { workerLog } from "./worker_log.ts";

const LOG_OUTPUT_CHARS = 4_000;

/** 在真正执行前打出命令清单，避免验证阶段只有心跳、没有原因。 */
export function logVerificationPlan(commands: VerificationCommand[]): void {
  workerLog(`开始 Worker 验证：共 ${commands.length} 条`);
  for (let index = 0; index < commands.length; index += 1) {
    const command = commands[index]!;
    workerLog(
      `验证命令 ${index + 1}/${commands.length}：` +
        `${summarizeCommand(command.executable, command.args)} ` +
        `cwd=${command.cwd?.trim() || "."}`,
    );
  }
}

/** 记账到看板之前先写出每条结果，防止 MCP 拒收时吞掉真实失败原因。 */
export function logVerificationResults(results: VerificationResult[]): void {
  for (let index = 0; index < results.length; index += 1) {
    const result = results[index]!;
    const ordinal = `${index + 1}/${results.length}`;
    if (result.output.trim() === "因前序验证失败未执行") {
      workerLog(
        `验证跳过 ${ordinal}：${result.commandSummary}（因前序验证失败未执行）`,
        "worker",
        "warning",
      );
      continue;
    }
    if (result.passed) {
      workerLog(
        `验证通过 ${ordinal}：${result.commandSummary} 耗时=${result.durationMs}ms`,
        "worker",
        "success",
      );
      continue;
    }
    workerLog(
      `验证失败 ${ordinal}：${formatVerificationFailure(result)} 耗时=${result.durationMs}ms`,
      "worker",
      "error",
    );
    const output = result.output.trim();
    if (!output) {
      workerLog("验证无输出（进程可能未能启动）", "shell", "warning");
      continue;
    }
    workerLog(truncateLogOutput(output), "shell", "error");
  }
}

export function truncateLogOutput(output: string): string {
  if (output.length <= LOG_OUTPUT_CHARS) return output;
  return `${output.slice(0, LOG_OUTPUT_CHARS)}\n…（日志已截断，完整输出写入验证结果）`;
}
