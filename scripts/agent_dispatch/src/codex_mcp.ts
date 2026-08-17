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
import { applyDispatchArchitectureOverride } from "./dispatch_agents_overlay.ts";

const AUTH_FILES = ["auth.json"];
const USER_INSTRUCTION_DIRS = ["skills"];

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
  writeOverlayAgentsMarkdown(options.userCodexHome, home);
  for (const name of USER_INSTRUCTION_DIRS) {
    copyUserPath(
      join(options.userCodexHome, name),
      join(home, name),
    );
  }
  return { home, mcpServerNames: listCodexMcpServerNames(config) };
}

function writeOverlayAgentsMarkdown(userHome: string, destHome: string): void {
  const from = join(userHome, "AGENTS.md");
  const source = existsSync(from) ? readFileSync(from, "utf8") : "";
  const overlay = applyDispatchArchitectureOverride(source);
  writeFileSync(join(destHome, "AGENTS.md"), overlay, "utf8");
  writeFileSync(join(destHome, "AGENTS.override.md"), overlay, "utf8");
}

function copyUserPath(from: string, to: string): void {
  if (!existsSync(from)) return;
  if (statSync(from).isDirectory()) {
    cpSync(from, to, { recursive: true });
    return;
  }
  copyFileSync(from, to);
}
