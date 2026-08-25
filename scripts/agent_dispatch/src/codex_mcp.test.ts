import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
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
  it("\u65E0\u7528\u6237\u914D\u7F6E\u65F6\u53EA\u5305\u542B\u7CBE\u7B80\u770B\u677F MCP", () => {
    const text = buildCodexAgentConfigToml("http://127.0.0.1:19000/mcp");
    assert.match(text, /rmcp_client = true/);
    assert.match(text, /\[mcp_servers\.kanbanMCP\]/);
    assert.match(text, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
    assert.equal(text.includes("unityMCP"), false);
  });

  it("\u9694\u79BB\u4E3B\u76EE\u5F55\u590D\u5236 auth、AGENTS.md、skills；\u65E0\u6807\u7B7E\u65F6\u4E0D\u5408\u5E76\u7528\u6237 MCP", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-codex-mcp-"));
    try {
      const userHome = join(root, "user");
      mkdirSync(userHome);
      const cursorSkillsRoot = join(root, "cursor-skills");
      mkdirSync(join(cursorSkillsRoot, "kanban-complete-tasks"), {
        recursive: true,
      });
      writeFileSync(join(userHome, "auth.json"), '{"ok":true}', "utf8");
      writeFileSync(
        join(userHome, "AGENTS.md"),
        `# \u7528\u6237\u6307\u4EE4

\u52A8\u624B\u5199\u4EE3\u7801、\u6539\u6A21\u5757\u8FB9\u754C\u6216\u8BBE\u8BA1\u65B9\u6848\u524D，MUST \u5148\u9605\u8BFB：

- [\`docs/Architecture.md\`](docs/Architecture.md) — \u7CFB\u7EDF\u5206\u5C42
`,
        "utf8",
      );
      writeFileSync(
        join(cursorSkillsRoot, "kanban-complete-tasks", "SKILL.md"),
        "# kanban-complete-tasks\n",
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
        cursorSkillsRoot,
      });
      const auth = readFileSync(join(created.home, "auth.json"), "utf8");
      const config = readFileSync(join(created.home, "config.toml"), "utf8");
      const agents = readFileSync(join(created.home, "AGENTS.md"), "utf8");
      const skill = readFileSync(
        join(
          created.home,
          "skills",
          "kanban-complete-tasks",
          "SKILL.md",
        ),
        "utf8",
      );
      assert.equal(auth, '{"ok":true}');
      assert.match(agents, /# \u7528\u6237\u6307\u4EE4/);
      assert.match(agents, /MUST \u5148\u9605\u8BFB/);
      assert.equal(skill, "# kanban-complete-tasks\n");
      assert.equal(
        existsSync(join(created.home, "skills", "demo", "SKILL.md")),
        false,
      );
      assert.equal(config.includes("mcp_servers.other"), false);
      assert.match(config, /url = "http:\/\/127\.0\.0\.1:19000\/mcp"/);
      assert.equal(config.includes("18765"), false);
      assert.deepEqual(created.mcpServerNames, ["kanbanMCP"]);
      const labeled = createCodexAgentHome({
        mcpUrl: "http://127.0.0.1:19000/mcp",
        userCodexHome: userHome,
        tempRoot: root,
        projectMcpTags: ["other"],
        cursorSkillsRoot,
      });
      assert.deepEqual(labeled.mcpServerNames, ["other", "kanbanMCP"]);
      assert.equal(resolveUserCodexHome({ CODEX_HOME: "D:\\codex" }), "D:\\codex");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
