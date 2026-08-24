import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  createCursorSdkScanLogBuffer,
  formatCursorSdkScanNote,
  isAllowedByProjectSettingSource,
  parseCursorSdkScanLog,
} from "./cursor_sdk_scan_log.ts";

describe("parseCursorSdkScanLog", () => {
  it("\u89E3\u6790 Skill \u626B\u63CF\u884C（\u8FC7\u6EE4\u524D）", () => {
    const scan = parseCursorSdkScanLog(
      "03:44:15.020 INFO  AgentSkillsCursorRulesService load completed meta={durationMs: 119, ruleCount: 24, skillCount: 24}",
    );
    assert.deepEqual(scan, {
      kind: "skills",
      ruleCount: 24,
      skillCount: 24,
    });
    assert.match(
      formatCursorSdkScanNote(scan!),
      /SDK scanned Skills: 24.*select by trigger.*does not inject every Skill body/,
    );
  });

  it("\u89E3\u6790 Rule \u626B\u63CF\u884C（\u8FC7\u6EE4\u524D）", () => {
    const scan = parseCursorSdkScanLog(
      "03:44:15.011 INFO  LocalCursorRulesService load completed meta={durationMs: 113, ruleCount: 13}",
    );
    assert.deepEqual(scan, { kind: "rules", ruleCount: 13 });
    assert.match(
      formatCursorSdkScanNote(scan!),
      /SDK scanned Rules: 13.*User Rules are already written into the prompt/,
    );
  });

  it("\u5FFD\u7565\u65E0\u5173\u65E5\u5FD7", () => {
    assert.equal(parseCursorSdkScanLog("\u672C\u5730\u4F1A\u8BDD\u5DF2\u521B\u5EFA，\u5F00\u59CB\u6267\u884C…"), undefined);
  });
});

describe("isAllowedByProjectSettingSource", () => {
  const project = "C:/Users/me/Projects/kanban";

  it("\u542F\u7528 user \u8BBE\u7F6E\u5C42\u540E\u4FDD\u7559\u7528\u6237\u4E3B\u76EE\u5F55\u7684\u5185\u7F6E Skill \u4E0E\u7528\u6237 Rule", () => {
    assert.equal(
      isAllowedByProjectSettingSource(
        "C:\\Users\\me\\.cursor\\skills-cursor\\canvas\\SKILL.md",
        [project, "C:/Users/me"],
      ),
      true,
    );
    assert.equal(
      isAllowedByProjectSettingSource(
        "C:/Users/me/.cursor/rules/common/language.mdc",
        [project, "C:/Users/me"],
      ),
      true,
    );
  });

  it("\u4FDD\u7559\u4ED3\u5E93\u5185 Skill", () => {
    assert.equal(
      isAllowedByProjectSettingSource(
        `${project}/.cursor/skills/demo/SKILL.md`,
        [project],
      ),
      true,
    );
  });
});

describe("createCursorSdkScanLogBuffer", () => {
  it("\u62FC\u63A5\u5F85\u5B8C\u6574\u4E00\u884C\u518D\u51FA\u8BF4\u660E", () => {
    const notes: string[] = [];
    const buffer = createCursorSdkScanLogBuffer((note) => notes.push(note));
    buffer.push("03:44:15.020 INFO  AgentSkillsCursorRulesService load completed ");
    assert.deepEqual(notes, []);
    buffer.push("meta={skillCount: 24}\n");
    assert.equal(notes.length, 1);
    assert.match(notes[0] ?? "", /SDK scanned Skills: 24/);
  });
});
