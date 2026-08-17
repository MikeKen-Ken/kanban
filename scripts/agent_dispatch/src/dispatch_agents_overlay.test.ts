import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { applyDispatchArchitectureOverride } from "./dispatch_agents_overlay.ts";

describe("applyDispatchArchitectureOverride", () => {
  it("去掉必须再打开 Architecture.md 的条目，并保留 ADR / Systems", () => {
    const text = applyDispatchArchitectureOverride(`# 全局工作规则

## 开发前必读

动手写代码、改模块边界或设计方案前，MUST 先阅读：

- [\`docs/Architecture.md\`](docs/Architecture.md) — 系统分层、目录职责、数据流与模块边界

按需补充（与当前改动相关时 MUST 阅读）：

- [\`docs/Systems/\`](docs/Systems/) — 对应子系统说明
- 根目录 [\`CONTEXT.md\`](CONTEXT.md) — 领域术语（若存在）

- MUST NOT 在未读 \`Architecture.md\`（若存在）的情况下擅自新增顶层目录或跨层依赖。
`);
    assert.match(text, /本会话覆盖/);
    assert.match(text, /已由 Worker 注入，视为已读/);
    assert.match(text, /docs\/Systems\//);
    assert.match(text, /CONTEXT\.md/);
    assert.match(text, /未遵守已注入 Architecture\.md/);
    assert.equal(text.includes("MUST 先阅读"), false);
    assert.equal(text.includes("docs/Architecture.md]"), false);
  });

  it("没有用户 AGENTS.md 时仍写出覆盖说明", () => {
    const text = applyDispatchArchitectureOverride("");
    assert.match(text, /本会话覆盖/);
    assert.match(text, /视为已满足/);
  });
});
