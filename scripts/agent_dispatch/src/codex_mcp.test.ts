import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  buildCodexAgentConfigToml,
  createCodexAgentHome,
  resolveUserCodexHome,
} from "./codex_mcp.ts";

describe("codex_mcp", () => {
  it("无用户配置时只包含精简看板 MCP", () => {
    const text = buildCodexAgentConfigToml("http://127.0.0.1:19000/mcp");
    assert.match(text, /rmcp_client = true/);
    assert.match(text, /\[mcp_servers\.kanbanMCP\]/);
    assert.match(text, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
    assert.equal(text.includes("unityMCP"), false);
  });

  it("隔离主目录复制 auth、AGENTS.md、skills，并合并用户 MCP", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-codex-mcp-"));
    try {
      const userHome = join(root, "user");
      mkdirSync(userHome);
      mkdirSync(join(userHome, "skills", "demo"), { recursive: true });
      writeFileSync(join(userHome, "auth.json"), '{"ok":true}', "utf8");
      writeFileSync(join(userHome, "AGENTS.md"), "# 用户指令\n", "utf8");
      writeFileSync(
        join(userHome, "skills", "demo", "SKILL.md"),
        "# demo\n",
        "utf8",
      );
      writeFileSync(
        join(userHome, "config.toml"),
        `[mcp_servers.other]
url = "http://127.0.0.1:1/mcp"

[mcp_servers.kanbanMCP]
url = "http://127.0.0.1:18765/mcp"
`,
        "utf8",
      );
      const created = createCodexAgentHome({
        mcpUrl: "http://127.0.0.1:19000/mcp",
        userCodexHome: userHome,
        tempRoot: root,
      });
      const auth = readFileSync(join(created.home, "auth.json"), "utf8");
      const config = readFileSync(join(created.home, "config.toml"), "utf8");
      const agents = readFileSync(join(created.home, "AGENTS.md"), "utf8");
      const skill = readFileSync(
        join(created.home, "skills", "demo", "SKILL.md"),
        "utf8",
      );
      assert.equal(auth, '{"ok":true}');
      assert.equal(agents, "# 用户指令\n");
      assert.equal(skill, "# demo\n");
      assert.match(config, /mcp_servers\.other/);
      assert.match(config, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
      assert.equal(config.includes("18765"), false);
      assert.deepEqual(created.mcpServerNames, ["other", "kanbanMCP"]);
      assert.equal(resolveUserCodexHome({ CODEX_HOME: "D:\\codex" }), "D:\\codex");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
