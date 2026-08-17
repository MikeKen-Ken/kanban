import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  expandEnvTemplates,
  mergeCursorMcpServers,
} from "./cursor_mcp_servers.ts";

describe("cursor_mcp_servers", () => {
  it("合并用户与项目 MCP，并强制覆盖 kanbanMCP 为 scoped", () => {
    const servers = mergeCursorMcpServers({
      userJson: JSON.stringify({
        mcpServers: {
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
    const unity = servers.unityMCP;
    const cocos = servers["cocos-creator"];
    const kanban = servers.kanbanMCP;
    const tavily = servers.tavily;
    assert.ok(unity && "url" in unity);
    assert.equal(unity.url, "http://127.0.0.1:8080/mcp");
    assert.ok(cocos && "url" in cocos);
    assert.equal(cocos.url, "http://127.0.0.1:3000/mcp");
    assert.ok(kanban && "url" in kanban);
    assert.equal(kanban.url, "http://127.0.0.1:19000/mcp");
    assert.equal(kanban.type, "http");
    assert.ok(tavily && "env" in tavily);
    assert.equal(tavily.env?.TAVILY_API_KEY, "from-env");
    assert.equal(Object.hasOwn(servers, "kanbanMCP"), true);
  });

  it("用户 JSON 损坏时仍注入 scoped 看板 MCP", () => {
    const servers = mergeCursorMcpServers({
      userJson: "{not json",
      scopedKanbanUrl: "http://127.0.0.1:1/mcp",
    });
    assert.deepEqual(Object.keys(servers), ["kanbanMCP"]);
    assert.ok(servers.kanbanMCP && "url" in servers.kanbanMCP);
    assert.equal(servers.kanbanMCP.url, "http://127.0.0.1:1/mcp");
  });

  it("只展开已存在的环境变量模板", () => {
    const env = { HOME: "/tmp/home" };
    assert.equal(expandEnvTemplates("${env:HOME}/x", env), "/tmp/home/x");
    assert.equal(expandEnvTemplates("${env:MISSING}/x", env), "${env:MISSING}/x");
  });
});
