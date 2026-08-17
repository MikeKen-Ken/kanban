import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  buildCodexAgentConfigToml,
  listCodexMcpServerNames,
  stripKanbanMcpTables,
} from "./codex_agent_config.ts";

describe("codex_agent_config", () => {
  it("无用户配置时只写 scoped 看板 MCP", () => {
    const text = buildCodexAgentConfigToml("http://127.0.0.1:19000/mcp");
    assert.match(text, /rmcp_client = true/);
    assert.match(text, /\[mcp_servers\.kanbanMCP\]/);
    assert.match(text, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
    assert.equal(text.includes("unityMCP"), false);
  });

  it("无项目标签时仅保留 hubMCP 与 scoped 看板 MCP，并去掉完整看板 MCP", () => {
    const user = `
[mcp_servers.hubMCP]
command = "node"

[mcp_servers.kanbanMCP.tools.list_board]
enabled = true

[mcp_servers.unityMCP]
url = "http://127.0.0.1:8080/mcp"

[mcp_servers.tavily.env]
TAVILY_API_KEY = "secret"

[mcp_servers.kanbanMCP]
url = "http://127.0.0.1:18765/mcp"

[mcp_servers.tavily]
command = "npx"
`;
    const text = buildCodexAgentConfigToml("http://127.0.0.1:19000/mcp", user);
    assert.equal(text.includes("unityMCP"), false);
    assert.equal(text.includes("tavily"), false);
    assert.match(text, /\[mcp_servers\.hubMCP\]/);
    assert.match(text, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
    assert.equal(text.includes("18765"), false);
    assert.deepEqual(listCodexMcpServerNames(text), ["hubMCP", "kanbanMCP"]);
  });

  it("按项目标签放行对应 MCP，并去掉完整看板 MCP 及其子表", () => {
    const user = `
[mcp_servers.hubMCP]
command = "node"

[mcp_servers.kanbanMCP.tools.list_board]
enabled = true

[mcp_servers.unityMCP]
url = "http://127.0.0.1:8080/mcp"

[mcp_servers.tavily.env]
TAVILY_API_KEY = "secret"

[mcp_servers.kanbanMCP]
url = "http://127.0.0.1:18765/mcp"

[mcp_servers.tavily]
command = "npx"
`;
    const text = buildCodexAgentConfigToml(
      "http://127.0.0.1:19000/mcp",
      user,
      ["unity", "tavily"],
    );
    assert.match(text, /\[mcp_servers\.hubMCP\]/);
    assert.match(text, /\[mcp_servers\.unityMCP\]/);
    assert.match(text, /\[mcp_servers\.tavily\]/);
    assert.match(text, /TAVILY_API_KEY = "secret"/);
    assert.match(text, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
    assert.equal(text.includes("18765"), false);
    assert.equal(text.includes("list_board"), false);
    assert.deepEqual(listCodexMcpServerNames(text), [
      "hubMCP",
      "unityMCP",
      "tavily",
      "kanbanMCP",
    ]);
  });

  it("strip 只删除看板表，保留根级其它配置", () => {
    const source = `model = "gpt-5.6"
[mcp_servers.kanbanMCP]
url = "http://127.0.0.1:18765/mcp"
[features]
rmcp_client = true
`;
    const stripped = stripKanbanMcpTables(source);
    assert.match(stripped, /model = "gpt-5.6"/);
    assert.match(stripped, /\[features\]/);
    assert.equal(stripped.includes("kanbanMCP"), false);
  });
});
