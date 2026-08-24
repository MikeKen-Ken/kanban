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
  it("\u7A7A\u89C4\u5219\u4E5F\u5305\u4E00\u5C42，\u4FBF\u4E8E\u8BA1\u6570", () => {
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

  it("\u6B63\u6587\u53EA\u51FA\u73B0\u5728\u5305\u88F9\u5185\u4FA7\u4E00\u6B21", () => {
    const wrapped = wrapWorkerUserRules(`\u524D\u8A00\n${USER_RULE_FILE_CANARY}\n`);
    assert.equal(wrapped.split(WORKER_USER_RULES_BEGIN).length - 1, 1);
    assert.equal(wrapped.split(WORKER_USER_RULES_END).length - 1, 1);
    assert.equal(wrapped.split(USER_RULE_FILE_CANARY).length - 1, 1);
    assert.match(wrapped, new RegExp(
      `${WORKER_USER_RULES_BEGIN}\\n[\\s\\S]*${USER_RULE_FILE_CANARY}[\\s\\S]*\\n${WORKER_USER_RULES_END}`,
    ));
    assert.equal(wrapped.includes(ALWAYS_APPLY_USER_RULE_CANARY), false);
  });
});
