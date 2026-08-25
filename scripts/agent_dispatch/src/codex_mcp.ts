import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import {
  buildCodexAgentConfigToml,
  listCodexMcpServerNames,
} from "./codex_agent_config.ts";

const AUTH_FILES = ["auth.json"];
const CURSOR_SKILL_NAME = "kanban-complete-tasks";

export { buildCodexAgentConfigToml, listCodexMcpServerNames };

export function resolveUserCodexHome(
  env: NodeJS.ProcessEnv = process.env,
): string {
  const override = env.CODEX_HOME?.trim();
  if (override) return override;
  return join(homedir(), ".codex");
}

export function createCodexAgentHome(options: {
  mcpUrl: string;
  userCodexHome: string;
  projectMcpTags?: readonly string[];
  tempRoot?: string;
  cursorSkillsRoot?: string;
}): { home: string; mcpServerNames: string[] } {
  const prefix = join(
    options.tempRoot ?? tmpdir(),
    "kanban-codex-home-",
  );
  const home = mkdtempSync(prefix);
  mkdirSync(home, { recursive: true });
  const userConfigPath = join(options.userCodexHome, "config.toml");
  const userConfig = existsSync(userConfigPath)
    ? readFileSync(userConfigPath, "utf8")
    : "";
  const config = buildCodexAgentConfigToml(
    options.mcpUrl,
    userConfig,
    options.projectMcpTags ?? [],
  );
  writeFileSync(join(home, "config.toml"), config, "utf8");
  for (const name of AUTH_FILES) {
    copyUserPath(
      join(options.userCodexHome, name),
      join(home, name),
    );
  }
  copyUserPath(join(options.userCodexHome, "AGENTS.md"), join(home, "AGENTS.md"));
  copyUserPath(
    join(
      options.cursorSkillsRoot ?? join(homedir(), ".cursor", "skills"),
      CURSOR_SKILL_NAME,
    ),
    join(home, "skills", CURSOR_SKILL_NAME),
  );
  return { home, mcpServerNames: listCodexMcpServerNames(config) };
}

function copyUserPath(from: string, to: string): void {
  if (!existsSync(from)) return;
  if (statSync(from).isDirectory()) {
    cpSync(from, to, { recursive: true });
    return;
  }
  copyFileSync(from, to);
}
