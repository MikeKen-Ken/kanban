import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  createCursorSdkScanLogBuffer,
  formatCursorSdkScanNote,
  isAllowedByProjectSettingSource,
  parseCursorSdkScanLog,
} from "./cursor_sdk_scan_log.ts";

describe("parseCursorSdkScanLog", () => {
  it("解析 Skill 扫描行（过滤前）", () => {
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
      /SDK 扫描 Skill：24 个.*触发条件选择.*不会将全部 Skill 正文同时注入/,
    );
  });

  it("解析 Rule 扫描行（过滤前）", () => {
    const scan = parseCursorSdkScanLog(
      "03:44:15.011 INFO  LocalCursorRulesService load completed meta={durationMs: 113, ruleCount: 13}",
    );
    assert.deepEqual(scan, { kind: "rules", ruleCount: 13 });
    assert.match(
      formatCursorSdkScanNote(scan!),
      /SDK 扫描 Rule：13 个.*用户 Rule 已由 Worker 写入 prompt/,
    );
  });

  it("忽略无关日志", () => {
    assert.equal(parseCursorSdkScanLog("本地会话已创建，开始执行…"), undefined);
  });
});

describe("isAllowedByProjectSettingSource", () => {
  const project = "C:/Users/me/Projects/kanban";

  it("启用 user 设置层后保留用户主目录的内置 Skill 与用户 Rule", () => {
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

  it("保留仓库内 Skill", () => {
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
  it("拼接待完整一行再出说明", () => {
    const notes: string[] = [];
    const buffer = createCursorSdkScanLogBuffer((note) => notes.push(note));
    buffer.push("03:44:15.020 INFO  AgentSkillsCursorRulesService load completed ");
    assert.deepEqual(notes, []);
    buffer.push("meta={skillCount: 24}\n");
    assert.equal(notes.length, 1);
    assert.match(notes[0] ?? "", /SDK 扫描 Skill：24 个/);
  });
});
