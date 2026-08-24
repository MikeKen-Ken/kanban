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
  it("\u5728\u4ED3\u5E93\u5185\u76F8\u5BF9 cwd \u6267\u884C\u5E76\u8BB0\u5F55\u8017\u65F6", async () => {
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

  it("\u9047\u5230\u9996\u4E2A\u5931\u8D25\u540E\u505C\u6B62\u540E\u7EED\u547D\u4EE4", async () => {
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
    assert.equal(filled[1]?.output, "Skipped because a previous validation failed");
  });

  it("\u8D85\u65F6\u547D\u4EE4\u4F1A\u88AB\u7EC8\u6B62\u5E76\u6807\u8BB0 124", async () => {
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

  it("\u62D2\u7EDD cwd \u9003\u51FA\u4ED3\u5E93", async () => {
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
    assert.match(result.output, /escaped the repository/);
  });

  it("args \u4E0D\u7ECF\u8FC7 shell \u5C55\u5F00", async () => {
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

  it("\u627E\u4E0D\u5230\u53EF\u6267\u884C\u6587\u4EF6\u65F6\u8BF4\u660E Worker PATH \u53EF\u80FD\u4E0D\u542B Flutter", async () => {
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
    assert.match(result.output, /Executable kanban-definitely-missing-binary was not found/);
    assert.match(result.output, /ENOENT/);
    assert.match(result.output, /Kanban process PATH/);
  });

  it("timeout \u4F1A\u94B3\u5236 Worker \u4E0A\u9650", () => {
    assert.equal(clampTimeout(Number.MAX_SAFE_INTEGER), MAX_VERIFICATION_TIMEOUT_MS);
  });

  it("\u5931\u8D25\u539F\u56E0\u9644\u5E26\u8F93\u51FA\u9996\u884C，\u4FBF\u4E8E\u5B9A\u4F4D spawn ENOENT", () => {
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
      "Verification command failed (exitCode=-1): flutter test targeted.dart; spawn flutter ENOENT",
    );
  });

  it("\u8DF3\u8FC7 stdout/stderr \u6807\u7B7E，\u4F18\u5148\u4F7F\u7528 issues found \u6458\u8981", () => {
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
      "Verification command failed (exitCode=1): flutter analyze; 44 issues found. (ran in 72.7s)",
    );
  });
});
