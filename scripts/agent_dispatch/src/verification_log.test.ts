import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { truncateLogOutput } from "./verification_log.ts";
import { describeMissingExecutable } from "./verification_runner.ts";

describe("verification_log", () => {
  it("截断过长验证输出并保留开头", () => {
    const output = "a".repeat(5000);
    const truncated = truncateLogOutput(output);
    assert.equal(truncated.startsWith("a".repeat(4000)), true);
    assert.match(truncated, /日志已截断/);
  });
});

describe("describeMissingExecutable", () => {
  it("点明 ENOENT 与看板进程 PATH", () => {
    assert.match(describeMissingExecutable("flutter"), /未找到可执行文件 flutter/);
    assert.match(describeMissingExecutable("flutter"), /ENOENT/);
    assert.match(describeMissingExecutable("flutter"), /看板进程的 PATH/);
  });
});
