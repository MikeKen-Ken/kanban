import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  expandEnvTemplates,
  mergeCursorMcpServers,
} from "./cursor_mcp_servers.ts";

describe("cursor_mcp_servers", () => {
  it("\u65E0\u9879\u76EE\u6807\u7B7E\u65F6\u53EA\u6CE8\u5165 scoped \u770B\u677F MCP", () => {
    const servers = mergeCursorMcpServers({
      userJson: JSON.stringify({
        mcpServers: {
          hubMCP: { command: "node", args: ["hub.js"] },
          unityMCP: { url: "http://127.0.0.1:8080/mcp", type: "http" },
          kanbanMCP: { url: "http://127.0.0.1:18765/mcp", type: "http" },
          tavily: {
            command: "npx",
            args: ["-y", "mcp-remote"],
            env: { TAVILY_API_KEY: "${env:TAVILY_API_KEY}" },
          },
        },
      }),
      projectJson: JSON.stringify({
        mcpServers: {
          "cocos-creator": { url: "http://127.0.0.1:3000/mcp" },
        },
      }),
      scopedKanbanUrl: "http://127.0.0.1:19000/mcp",
      env: { TAVILY_API_KEY: "from-env" },
    });
    assert.deepEqual(Object.keys(servers), ["kanbanMCP"]);
    assert.equal(servers.hubMCP, undefined);
    const kanban = servers.kanbanMCP;
    assert.ok(kanban && "url" in kanban);
    assert.equal(kanban.url, "http://127.0.0.1:19000/mcp");
    assert.equal(kanban.type, "http");
  });

  it("\u6309\u9879\u76EE\u6807\u7B7E\u653E\u884C\u5BF9\u5E94 MCP，\u5E76\u5F3A\u5236\u8986\u76D6 kanbanMCP \u4E3A scoped", () => {
    const servers = mergeCursorMcpServers({
      userJson: JSON.stringify({
        mcpServers: {
          hubMCP: { command: "node", args: ["hub.js"] },
          unityMCP: { url: "http://127.0.0.1:8080/mcp", type: "http" },
          kanbanMCP: { url: "http://127.0.0.1:18765/mcp", type: "http" },
          tavily: {
            command: "npx",
            args: ["-y", "mcp-remote"],
            env: { TAVILY_API_KEY: "${env:TAVILY_API_KEY}" },
          },
        },
      }),
      projectJson: JSON.stringify({
        mcpServers: {
          "cocos-creator": { url: "http://127.0.0.1:3000/mcp" },
        },
      }),
      scopedKanbanUrl: "http://127.0.0.1:19000/mcp",
      projectMcpTags: ["unity", "tavily"],
      env: { TAVILY_API_KEY: "from-env" },
    });
    assert.equal(servers.hubMCP, undefined);
    const unity = servers.unityMCP;
    const kanban = servers.kanbanMCP;
    const tavily = servers.tavily;
    assert.ok(unity && "url" in unity);
    assert.equal(unity.url, "http://127.0.0.1:8080/mcp");
    assert.equal(servers["cocos-creator"], undefined);
    assert.ok(kanban && "url" in kanban);
    assert.equal(kanban.url, "http://127.0.0.1:19000/mcp");
    assert.ok(tavily && "env" in tavily);
    assert.equal(tavily.env?.TAVILY_API_KEY, "from-env");
  });

  it("\u7528\u6237 JSON \u635F\u574F\u65F6\u4ECD\u6CE8\u5165 scoped \u770B\u677F MCP", () => {
    const servers = mergeCursorMcpServers({
      userJson: "{not json",
      scopedKanbanUrl: "http://127.0.0.1:1/mcp",
    });
    assert.deepEqual(Object.keys(servers), ["kanbanMCP"]);
    assert.ok(servers.kanbanMCP && "url" in servers.kanbanMCP);
    assert.equal(servers.kanbanMCP.url, "http://127.0.0.1:1/mcp");
  });

  it("\u53EA\u5C55\u5F00\u5DF2\u5B58\u5728\u7684\u73AF\u5883\u53D8\u91CF\u6A21\u677F", () => {
    const env = { HOME: "/tmp/home" };
    assert.equal(expandEnvTemplates("${env:HOME}/x", env), "/tmp/home/x");
    assert.equal(expandEnvTemplates("${env:MISSING}/x", env), "${env:MISSING}/x");
  });
});
