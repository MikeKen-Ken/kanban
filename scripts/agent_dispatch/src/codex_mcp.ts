import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const AUTH_FILES = ["auth.json"];
const USER_INSTRUCTION_FILES = ["AGENTS.md"];
const USER_INSTRUCTION_DIRS = ["skills"];

export function buildCodexAgentConfigToml(mcpUrl: string): string {
  const url = mcpUrl.trim();
  return `[features]
rmcp_client = true

[mcp_servers.kanbanMCP]
url = "${url}"
`;
}

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
  tempRoot?: string;
}): { home: string } {
  const prefix = join(
    options.tempRoot ?? tmpdir(),
    "kanban-codex-home-",
  );
  const home = mkdtempSync(prefix);
  mkdirSync(home, { recursive: true });
  writeFileSync(
    join(home, "config.toml"),
    buildCodexAgentConfigToml(options.mcpUrl),
    "utf8",
  );
  for (const name of AUTH_FILES) {
    copyUserPath(
      join(options.userCodexHome, name),
      join(home, name),
    );
  }
  for (const name of USER_INSTRUCTION_FILES) {
    copyUserPath(
      join(options.userCodexHome, name),
      join(home, name),
    );
  }
  for (const name of USER_INSTRUCTION_DIRS) {
    copyUserPath(
      join(options.userCodexHome, name),
      join(home, name),
    );
  }
  return { home };
}

function copyUserPath(from: string, to: string): void {
  if (!existsSync(from)) return;
  if (statSync(from).isDirectory()) {
    cpSync(from, to, { recursive: true });
    return;
  }
  copyFileSync(from, to);
}
