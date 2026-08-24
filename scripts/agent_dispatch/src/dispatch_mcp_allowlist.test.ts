import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  allowedMcpServerNames,
  filterRecordByMcpAllowlist,
  parseProjectMcpTags,
} from "./dispatch_mcp_allowlist.ts";

describe("dispatch_mcp_allowlist", () => {
  it("\u65E0\u9879\u76EE\u6807\u7B7E\u65F6\u4E0D\u6CE8\u5165 hubMCP", () => {
    assert.deepEqual([...allowedMcpServerNames([])], []);
    assert.deepEqual(
      filterRecordByMcpAllowlist(
        { aseprite: 1, kanbanMCP: 2, hubMCP: 3 },
        [],
      ),
      {},
    );
  });

  it("unity \u6807\u7B7E\u540C\u65F6\u653E\u884C\u4E24\u79CD\u670D\u52A1\u5668\u540D", () => {
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

  it("chrome \u522B\u540D\u6620\u5C04\u5230 chrome-devtools", () => {
    const allowed = allowedMcpServerNames(["chrome"]);
    assert.equal(allowed.has("hubMCP"), false);
    assert.equal(allowed.has("chrome-devtools"), true);
  });

  it("hub \u6807\u7B7E\u624D\u653E\u884C hubMCP", () => {
    assert.equal(allowedMcpServerNames(["hub"]).has("hubMCP"), true);
    assert.equal(
      filterRecordByMcpAllowlist({ hubMCP: 1, unityMCP: 2 }, ["hub"]).hubMCP,
      1,
    );
  });

  it("\u672A\u767B\u8BB0\u7684\u6807\u7B7E\u6309\u670D\u52A1\u5668\u540D\u7CBE\u786E\u653E\u884C", () => {
    assert.deepEqual(
      filterRecordByMcpAllowlist({ other: 1, tavily: 2 }, ["other"]),
      { other: 1 },
    );
  });

  it("\u4ECE claim JSON \u8BFB\u53D6\u9879\u76EE MCP \u6807\u7B7E", () => {
    assert.deepEqual(
      parseProjectMcpTags({
        projectMcpTags: ["unity", " unity", "", 1, "cocos"],
      }),
      ["unity", "cocos"],
    );
    assert.deepEqual(parseProjectMcpTags({}), []);
  });
});
