import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  MAX_VERIFICATION_TIMEOUT_MS,
  clampTimeout,
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

  it("timeout 会钳制 Worker 上限", () => {
    assert.equal(clampTimeout(Number.MAX_SAFE_INTEGER), MAX_VERIFICATION_TIMEOUT_MS);
  });
});
