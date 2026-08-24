import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  buildCodexAgentConfigToml,
  listCodexMcpServerNames,
  stripKanbanMcpTables,
} from "./codex_agent_config.ts";

describe("codex_agent_config", () => {
  it("\u65E0\u7528\u6237\u914D\u7F6E\u65F6\u53EA\u5199 scoped \u770B\u677F MCP", () => {
    const text = buildCodexAgentConfigToml("http://127.0.0.1:19000/mcp");
    assert.match(text, /rmcp_client = true/);
    assert.match(text, /\[mcp_servers\.kanbanMCP\]/);
    assert.match(text, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
    assert.equal(text.includes("unityMCP"), false);
  });

  it("\u65E0\u9879\u76EE\u6807\u7B7E\u65F6\u53EA\u4FDD\u7559 scoped \u770B\u677F MCP，\u5E76\u53BB\u6389\u5B8C\u6574\u770B\u677F MCP", () => {
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
    assert.equal(text.includes("hubMCP"), false);
    assert.match(text, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
    assert.equal(text.includes("18765"), false);
    assert.deepEqual(listCodexMcpServerNames(text), ["kanbanMCP"]);
  });

  it("\u6309\u9879\u76EE\u6807\u7B7E\u653E\u884C\u5BF9\u5E94 MCP，\u5E76\u53BB\u6389\u5B8C\u6574\u770B\u677F MCP \u53CA\u5176\u5B50\u8868", () => {
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
    assert.equal(text.includes("hubMCP"), false);
    assert.match(text, /\[mcp_servers\.unityMCP\]/);
    assert.match(text, /\[mcp_servers\.tavily\]/);
    assert.match(text, /TAVILY_API_KEY = "secret"/);
    assert.match(text, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
    assert.equal(text.includes("18765"), false);
    assert.equal(text.includes("list_board"), false);
    assert.deepEqual(listCodexMcpServerNames(text), [
      "unityMCP",
      "tavily",
      "kanbanMCP",
    ]);
  });

  it("strip \u53EA\u5220\u9664\u770B\u677F\u8868，\u4FDD\u7559\u6839\u7EA7\u5176\u5B83\u914D\u7F6E", () => {
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
