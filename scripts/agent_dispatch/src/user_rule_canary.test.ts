import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  ALWAYS_APPLY_USER_RULE_CANARY,
  USER_RULE_FILE_CANARY,
  WORKER_USER_RULES_BEGIN,
  WORKER_USER_RULES_END,
  wrapWorkerUserRules,
} from "./user_rule_canary.ts";

describe("wrapWorkerUserRules", () => {
  it("空规则也包一层，便于计数", () => {
    const wrapped = wrapWorkerUserRules("  ");
    assert.equal(
      wrapped,
      [
        WORKER_USER_RULES_BEGIN,
        "No user ~/.cursor/rules found.",
        WORKER_USER_RULES_END,
      ].join("\n"),
    );
  });

  it("正文只出现在包裹内侧一次", () => {
    const wrapped = wrapWorkerUserRules(`前言\n${USER_RULE_FILE_CANARY}\n`);
    assert.equal(wrapped.split(WORKER_USER_RULES_BEGIN).length - 1, 1);
    assert.equal(wrapped.split(WORKER_USER_RULES_END).length - 1, 1);
    assert.equal(wrapped.split(USER_RULE_FILE_CANARY).length - 1, 1);
    assert.match(wrapped, new RegExp(
      `${WORKER_USER_RULES_BEGIN}\\n[\\s\\S]*${USER_RULE_FILE_CANARY}[\\s\\S]*\\n${WORKER_USER_RULES_END}`,
    ));
    assert.equal(wrapped.includes(ALWAYS_APPLY_USER_RULE_CANARY), false);
  });
});
