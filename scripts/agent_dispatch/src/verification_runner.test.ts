import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  MAX_VERIFICATION_TIMEOUT_MS,
  clampTimeout,
  fillSkippedVerificationResults,
  formatVerificationFailure,
  runVerificationCommand,
  runVerificationCommands,
} from "./verification_runner.ts";

describe("verification_runner", () => {
  it("在仓库内相对 cwd 执行并记录耗时", async () => {
    const result = await runVerificationCommand(
      {
        executable: process.execPath,
        args: ["-e", "console.log(process.cwd())"],
        cwd: "src",
        expectedExitCode: 0,
      },
      process.cwd(),
    );

    assert.equal(result.passed, true);
    assert.match(result.output, /src$/i);
    assert.equal(result.cwd, "src");
    assert.ok(result.durationMs >= 0);
  });

  it("遇到首个失败后停止后续命令", async () => {
    const results = await runVerificationCommands(
      [
        { executable: process.execPath, args: ["-e", "process.exit(7)"] },
        { executable: process.execPath, args: ["-e", "process.exit(0)"] },
      ],
      process.cwd(),
    );

    assert.equal(results.length, 1);
    assert.equal(results[0]?.exitCode, 7);
    assert.equal(results[0]?.passed, false);

    const filled = fillSkippedVerificationResults(
      [
        { executable: process.execPath, args: ["-e", "process.exit(7)"] },
        { executable: process.execPath, args: ["-e", "process.exit(0)"], cwd: "src" },
      ],
      results,
    );
    assert.equal(filled.length, 2);
    assert.equal(filled[0]?.exitCode, 7);
    assert.equal(filled[1]?.passed, false);
    assert.equal(filled[1]?.exitCode, -1);
    assert.equal(filled[1]?.cwd, "src");
    assert.equal(filled[1]?.output, "因前序验证失败未执行");
  });

  it("超时命令会被终止并标记 124", async () => {
    const result = await runVerificationCommand(
      {
        executable: process.execPath,
        args: ["-e", "setTimeout(() => {}, 5000)"],
        timeoutMs: 20,
      },
      process.cwd(),
    );

    assert.equal(result.timedOut, true);
    assert.equal(result.exitCode, 124);
    assert.equal(result.passed, false);
  });

  it("拒绝 cwd 逃出仓库", async () => {
    const result = await runVerificationCommand(
      {
        executable: process.execPath,
        args: ["-e", "process.exit(0)"],
        cwd: "..",
      },
      process.cwd(),
    );

    assert.equal(result.passed, false);
    assert.equal(result.exitCode, -1);
    assert.match(result.output, /逃出仓库/);
  });

  it("args 不经过 shell 展开", async () => {
    const literal = "$HOME && echo injected";
    const result = await runVerificationCommand(
      {
        executable: process.execPath,
        args: ["-e", "console.log(process.argv[1])", literal],
      },
      process.cwd(),
    );

    assert.equal(result.passed, true);
    assert.equal(result.output, literal);
  });

  it("找不到可执行文件时说明 Worker PATH 可能不含 Flutter", async () => {
    const result = await runVerificationCommand(
      {
        executable: "kanban-definitely-missing-binary",
        args: ["test", "targeted.dart"],
        cwd: ".",
      },
      process.cwd(),
    );

    assert.equal(result.passed, false);
    assert.equal(result.exitCode, -1);
    assert.match(result.output, /未找到可执行文件 kanban-definitely-missing-binary/);
    assert.match(result.output, /ENOENT/);
    assert.match(result.output, /看板进程的 PATH/);
  });

  it("timeout 会钳制 Worker 上限", () => {
    assert.equal(clampTimeout(Number.MAX_SAFE_INTEGER), MAX_VERIFICATION_TIMEOUT_MS);
  });

  it("失败原因附带输出首行，便于定位 spawn ENOENT", () => {
    assert.equal(
      formatVerificationFailure({
        commandSummary: "flutter test targeted.dart",
        executable: "flutter",
        args: ["test", "targeted.dart"],
        cwd: "app",
        exitCode: -1,
        durationMs: 12,
        output: "spawn flutter ENOENT",
        timedOut: false,
        passed: false,
      }),
      "验证命令失败（exitCode=-1）：flutter test targeted.dart；spawn flutter ENOENT",
    );
  });

  it("跳过 stdout/stderr 标签，优先使用 issues found 摘要", () => {
    assert.equal(
      formatVerificationFailure({
        commandSummary: "flutter analyze",
        executable: "flutter",
        args: ["analyze"],
        cwd: "app",
        exitCode: 1,
        durationMs: 72700,
        output:
          "stdout:\ninfo - Use const\n\nstderr:\n44 issues found. (ran in 72.7s)",
        timedOut: false,
        passed: false,
      }),
      "验证命令失败（exitCode=1）：flutter analyze；44 issues found. (ran in 72.7s)",
    );
  });
});
