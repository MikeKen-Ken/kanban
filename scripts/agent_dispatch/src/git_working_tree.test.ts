import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { describe, it } from "node:test";
import { inspectGitWorkingTree } from "./git_working_tree.ts";

describe("git_working_tree", () => {
  it("区分 clean、dirty 与非 Git 目录", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-git-tree-"));
    try {
      assert.equal(inspectGitWorkingTree(root).kind, "not_git");
      execFileSync("git", ["init"], { cwd: root, stdio: "ignore" });
      writeFileSync(join(root, "tracked.txt"), "初始\n", "utf8");
      execFileSync("git", ["add", "-A"], { cwd: root, stdio: "ignore" });
      execFileSync("git", [
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.com",
        "commit",
        "-m",
        "initial",
      ], { cwd: root, stdio: "ignore" });
      assert.equal(inspectGitWorkingTree(root).kind, "clean");

      writeFileSync(join(root, "tracked.txt"), "修改\n", "utf8");
      const dirty = inspectGitWorkingTree(root);
      assert.equal(dirty.kind, "dirty");
      assert.match("output" in dirty ? dirty.output : "", /tracked\.txt/);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
