import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { applyDispatchArchitectureOverride } from "./dispatch_agents_overlay.ts";

describe("applyDispatchArchitectureOverride", () => {
  it("\u53BB\u6389\u5FC5\u987B\u518D\u6253\u5F00 Architecture.md \u7684\u6761\u76EE，\u5E76\u4FDD\u7559 ADR / Systems", () => {
    const text = applyDispatchArchitectureOverride(`# \u5168\u5C40\u5DE5\u4F5C\u89C4\u5219

## \u5F00\u53D1\u524D\u5FC5\u8BFB

\u52A8\u624B\u5199\u4EE3\u7801、\u6539\u6A21\u5757\u8FB9\u754C\u6216\u8BBE\u8BA1\u65B9\u6848\u524D，MUST \u5148\u9605\u8BFB：

- [\`docs/Architecture.md\`](docs/Architecture.md) — \u7CFB\u7EDF\u5206\u5C42、\u76EE\u5F55\u804C\u8D23、\u6570\u636E\u6D41\u4E0E\u6A21\u5757\u8FB9\u754C

\u6309\u9700\u8865\u5145（\u4E0E\u5F53\u524D\u6539\u52A8\u76F8\u5173\u65F6 MUST \u9605\u8BFB）：

- [\`docs/Systems/\`](docs/Systems/) — \u5BF9\u5E94\u5B50\u7CFB\u7EDF\u8BF4\u660E
- \u6839\u76EE\u5F55 [\`CONTEXT.md\`](CONTEXT.md) — \u9886\u57DF\u672F\u8BED（\u82E5\u5B58\u5728）

- MUST NOT \u5728\u672A\u8BFB \`Architecture.md\`（\u82E5\u5B58\u5728）\u7684\u60C5\u51B5\u4E0B\u64C5\u81EA\u65B0\u589E\u9876\u5C42\u76EE\u5F55\u6216\u8DE8\u5C42\u4F9D\u8D56。
`);
    assert.match(text, /This-session override/);
    assert.match(text, /already been injected by the Worker and counts as read/);
    assert.match(text, /docs\/Systems\//);
    assert.match(text, /CONTEXT\.md/);
    assert.match(text, /without following the injected Architecture.md/);
    assert.equal(text.includes("MUST \u5148\u9605\u8BFB"), false);
    assert.equal(text.includes("docs/Architecture.md]"), false);
  });

  it("\u6CA1\u6709\u7528\u6237 AGENTS.md \u65F6\u4ECD\u5199\u51FA\u8986\u76D6\u8BF4\u660E", () => {
    const text = applyDispatchArchitectureOverride("");
    assert.match(text, /This-session override/);
    assert.match(text, /treated as satisfied/);
  });
});
