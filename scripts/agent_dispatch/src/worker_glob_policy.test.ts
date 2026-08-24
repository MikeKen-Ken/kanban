import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { join } from "node:path";
import {
  DISPATCH_SEARCH_POLICY,
  evaluateGlobToolCall,
  globArgsFromUnknown,
  isGlobToolName,
  isUnboundedGlobPattern,
} from "./worker_glob_policy.ts";

const cwd = join("C:", "repo", "kanban");

describe("worker_glob_policy", () => {
  it("把仓库根 **/* 判为拒绝", () => {
    const result = evaluateGlobToolCall({
      pattern: "**/*",
      cwd,
    });
    assert.equal(result.allow, false);
    if (!result.allow) {
      assert.match(result.reason, /无界 glob/);
    }
  });

  it("允许子目录或带文件名片段的 glob", () => {
    assert.equal(
      evaluateGlobToolCall({
        pattern: "*",
        cwd,
      }).allow,
      true,
    );
    assert.equal(
      evaluateGlobToolCall({
        pattern: "**/*",
        targetDirectory: join(cwd, "app", "lib"),
        cwd,
      }).allow,
      true,
    );
  });

  it("拒绝 .git、.svn 与 build 目标", () => {
    assert.equal(
      evaluateGlobToolCall({
        pattern: "**/*",
        targetDirectory: join(cwd, ".git"),
        cwd,
      }).allow,
      false,
    );
    assert.equal(
      evaluateGlobToolCall({
        pattern: "**/*",
        targetDirectory: join(cwd, ".svn"),
        cwd,
      }).allow,
      false,
    );
    assert.equal(
      evaluateGlobToolCall({
        pattern: "*.dart",
        targetDirectory: join(cwd, "app", "build"),
        cwd,
      }).allow,
      false,
    );
  });

  it("识别无界模式与 glob 工具名，并保持搜索提示跨仓库通用", () => {
    assert.equal(isUnboundedGlobPattern("**/*"), true);
    assert.equal(isUnboundedGlobPattern("**/*attachment*"), false);
    assert.equal(isGlobToolName("Glob"), true);
    assert.equal(isGlobToolName("Read"), false);
    assert.match(DISPATCH_SEARCH_POLICY, /当前选定仓库/);
    assert.match(DISPATCH_SEARCH_POLICY, /项目规则/);
    assert.equal(DISPATCH_SEARCH_POLICY.includes("features/kanban"), false);
    assert.equal(DISPATCH_SEARCH_POLICY.includes("agent_dispatch/"), false);
  });

  it("从 hook JSON 抽出 glob 参数", () => {
    const args = globArgsFromUnknown({
      tool_name: "Glob",
      tool_input: {
        glob_pattern: "**/*",
        target_directory: cwd,
      },
      cwd,
    });
    assert.equal(args.pattern, "**/*");
    assert.equal(args.targetDirectory, cwd);
  });
});
