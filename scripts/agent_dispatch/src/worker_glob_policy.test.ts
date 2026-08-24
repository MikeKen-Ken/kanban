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
  it("\u628A\u4ED3\u5E93\u6839 **/* \u5224\u4E3A\u62D2\u7EDD", () => {
    const result = evaluateGlobToolCall({
      pattern: "**/*",
      cwd,
    });
    assert.equal(result.allow, false);
    if (!result.allow) {
      assert.match(result.reason, /unbounded-glob/);
    }
  });

  it("\u5141\u8BB8\u5B50\u76EE\u5F55\u6216\u5E26\u6587\u4EF6\u540D\u7247\u6BB5\u7684 glob", () => {
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

  it("\u62D2\u7EDD .git、.svn \u4E0E build \u76EE\u6807", () => {
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

  it("\u8BC6\u522B\u65E0\u754C\u6A21\u5F0F\u4E0E glob \u5DE5\u5177\u540D，\u5E76\u4FDD\u6301\u641C\u7D22\u63D0\u793A\u8DE8\u4ED3\u5E93\u901A\u7528", () => {
    assert.equal(isUnboundedGlobPattern("**/*"), true);
    assert.equal(isUnboundedGlobPattern("**/*attachment*"), false);
    assert.equal(isGlobToolName("Glob"), true);
    assert.equal(isGlobToolName("Read"), false);
    assert.match(DISPATCH_SEARCH_POLICY, /currently selected repository/);
    assert.match(DISPATCH_SEARCH_POLICY, /project rules/);
    assert.match(DISPATCH_SEARCH_POLICY, /confirm each directory exists/);
    assert.match(DISPATCH_SEARCH_POLICY, /rg --fixed-strings/);
    assert.equal(DISPATCH_SEARCH_POLICY.includes("features/kanban"), false);
    assert.equal(DISPATCH_SEARCH_POLICY.includes("agent_dispatch/"), false);
  });

  it("\u4ECE hook JSON \u62BD\u51FA glob \u53C2\u6570", () => {
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
