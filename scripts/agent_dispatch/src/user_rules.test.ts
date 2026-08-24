import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { readUserCursorRules } from "./user_rules.ts";
import { USER_RULE_FILE_CANARY } from "./user_rule_canary.ts";

describe("user_rules", () => {
  it("\u6309\u7A33\u5B9A\u987A\u5E8F\u5B8C\u6574\u6CE8\u5165\u6240\u6709 md/mdc \u7528\u6237 Rule", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-user-rules-"));
    mkdirSync(join(root, "nested"));
    writeFileSync(join(root, "b.mdc"), "\u89C4\u5219 B");
    writeFileSync(join(root, "nested", "a.md"), "\u89C4\u5219 A");
    writeFileSync(join(root, "ignored.json"), "{}\n");
    try {
      const bundle = readUserCursorRules(root);
      assert.equal(bundle.count, 2);
      assert.match(bundle.text, /\u89C4\u5219 B/);
      assert.match(bundle.text, /\u89C4\u5219 A/);
      assert.equal(bundle.text.includes("ignored.json"), false);
      assert.ok(bundle.text.indexOf("b.mdc") < bundle.text.indexOf("nested\/a.md"));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("\u4F1A\u5B8C\u6574\u590D\u5236 alwaysApply \u4E3A false \u7684\u6821\u9A8C\u89C4\u5219\u6587\u4EF6", () => {
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
