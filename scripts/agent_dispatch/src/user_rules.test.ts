import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { readUserCursorRules } from "./user_rules.ts";
import { USER_RULE_FILE_CANARY } from "./user_rule_canary.ts";

describe("user_rules", () => {
  it("按稳定顺序完整注入所有 md/mdc 用户 Rule", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-user-rules-"));
    mkdirSync(join(root, "nested"));
    writeFileSync(join(root, "b.mdc"), "规则 B");
    writeFileSync(join(root, "nested", "a.md"), "规则 A");
    writeFileSync(join(root, "ignored.json"), "{}\n");
    try {
      const bundle = readUserCursorRules(root);
      assert.equal(bundle.count, 2);
      assert.match(bundle.text, /规则 B/);
      assert.match(bundle.text, /规则 A/);
      assert.equal(bundle.text.includes("ignored.json"), false);
      assert.ok(bundle.text.indexOf("b.mdc") < bundle.text.indexOf("nested\/a.md"));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("会完整复制 alwaysApply 为 false 的校验规则文件", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-user-rules-canary-"));
    writeFileSync(
      join(root, "kanban-dispatch-canary.mdc"),
      `---\nalwaysApply: false\n---\n\n${USER_RULE_FILE_CANARY}\n`,
    );
    try {
      const bundle = readUserCursorRules(root);
      assert.equal(bundle.count, 1);
      assert.match(bundle.text, new RegExp(USER_RULE_FILE_CANARY));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
