import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  allowedMcpServerNames,
  filterRecordByMcpAllowlist,
  parseProjectMcpTags,
} from "./dispatch_mcp_allowlist.ts";

describe("dispatch_mcp_allowlist", () => {
  it("无项目标签时仍保留 hubMCP", () => {
    assert.deepEqual([...allowedMcpServerNames([])], ["hubMCP"]);
    assert.deepEqual(
      filterRecordByMcpAllowlist(
        { aseprite: 1, kanbanMCP: 2, hubMCP: 3 },
        [],
      ),
      { hubMCP: 3 },
    );
  });

  it("unity 标签同时放行两种服务器名", () => {
    const allowed = allowedMcpServerNames(["unity"]);
    assert.equal(allowed.has("unitymcp"), true);
    assert.equal(allowed.has("unityMCP"), true);
    assert.deepEqual(
      filterRecordByMcpAllowlist(
        {
          unityMCP: "a",
          aseprite: "b",
          "cocos-creator": "c",
        },
        ["unity"],
      ),
      { unityMCP: "a" },
    );
  });

  it("chrome 别名映射到 chrome-devtools", () => {
    const allowed = allowedMcpServerNames(["chrome"]);
    assert.equal(allowed.has("hubMCP"), true);
    assert.equal(allowed.has("chrome-devtools"), true);
  });

  it("未登记的标签按服务器名精确放行", () => {
    assert.deepEqual(
      filterRecordByMcpAllowlist({ other: 1, tavily: 2 }, ["other"]),
      { other: 1 },
    );
  });

  it("从 claim JSON 读取项目 MCP 标签", () => {
    assert.deepEqual(
      parseProjectMcpTags({
        projectMcpTags: ["unity", " unity", "", 1, "cocos"],
      }),
      ["unity", "cocos"],
    );
    assert.deepEqual(parseProjectMcpTags({}), []);
  });
});
