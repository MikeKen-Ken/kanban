import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { McpServerConfig } from "@cursor/sdk";
import { filterRecordByMcpAllowlist } from "./dispatch_mcp_allowlist.ts";

export const KANBAN_MCP_SERVER = "kanbanMCP";

export type CursorMcpServers = Record<string, McpServerConfig>;

export function scopedKanbanMcpServer(url: string): McpServerConfig {
  return { type: "http", url: url.trim() };
}

export function mergeCursorMcpServers(options: {
  userJson?: string | null;
  projectJson?: string | null;
  scopedKanbanUrl: string;
  projectMcpTags?: readonly string[];
  env?: NodeJS.ProcessEnv;
}): CursorMcpServers {
  const env = options.env ?? process.env;
  const merged: CursorMcpServers = {
    ...parseMcpServers(options.userJson, env),
    ...parseMcpServers(options.projectJson, env),
  };
  delete merged[KANBAN_MCP_SERVER];
  const allowed = filterRecordByMcpAllowlist(merged, options.projectMcpTags ?? []);
  allowed[KANBAN_MCP_SERVER] = scopedKanbanMcpServer(options.scopedKanbanUrl);
  return allowed;
}

export function loadCursorMcpServers(options: {
  cwd: string;
  scopedKanbanUrl: string;
  projectMcpTags?: readonly string[];
  homeDir?: string;
}): { servers: CursorMcpServers; names: string[] } {
  const home = options.homeDir ?? homedir();
  const servers = mergeCursorMcpServers({
    userJson: readOptionalFile(join(home, ".cursor", "mcp.json")),
    projectJson: readOptionalFile(join(options.cwd, ".cursor", "mcp.json")),
    scopedKanbanUrl: options.scopedKanbanUrl,
    projectMcpTags: options.projectMcpTags,
  });
  return { servers, names: Object.keys(servers) };
}

function parseMcpServers(
  raw: string | null | undefined,
  env: NodeJS.ProcessEnv,
): CursorMcpServers {
  if (raw == null || raw.trim() === "") return {};
  try {
    const decoded = JSON.parse(raw) as unknown;
    if (!isRecord(decoded)) return {};
    const servers = decoded.mcpServers;
    if (!isRecord(servers)) return {};
    const result: CursorMcpServers = {};
    for (const [name, value] of Object.entries(servers)) {
      if (name === KANBAN_MCP_SERVER) continue;
      const converted = toSdkServer(value, env);
      if (converted != null) result[name] = converted;
    }
    return result;
  } catch {
    return {};
  }
}

function toSdkServer(
  raw: unknown,
  env: NodeJS.ProcessEnv,
): McpServerConfig | null {
  if (!isRecord(raw)) return null;
  if (typeof raw.url === "string" && raw.url.trim() !== "") {
    const type = raw.type === "sse" ? "sse" : "http";
    const server: McpServerConfig = {
      type,
      url: expandEnvTemplates(raw.url.trim(), env),
    };
    if (isRecord(raw.headers)) {
      server.headers = expandStringRecord(raw.headers, env);
    }
    return server;
  }
  if (typeof raw.command === "string" && raw.command.trim() !== "") {
    const server: McpServerConfig = {
      command: expandEnvTemplates(raw.command.trim(), env),
    };
    if (Array.isArray(raw.args)) {
      server.args = raw.args
        .filter((item): item is string => typeof item === "string")
        .map((item) => expandEnvTemplates(item, env));
    }
    if (isRecord(raw.env)) {
      server.env = expandStringRecord(raw.env, env);
    }
    return server;
  }
  return null;
}

function expandStringRecord(
  record: Record<string, unknown>,
  env: NodeJS.ProcessEnv,
): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(record)) {
    if (typeof value === "string") {
      result[key] = expandEnvTemplates(value, env);
    }
  }
  return result;
}

export function expandEnvTemplates(
  value: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  return value.replace(/\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}/g, (original, name) => {
    const resolved = env[name as string];
    return resolved == null || resolved === "" ? original : resolved;
  });
}

function readOptionalFile(path: string): string | null {
  if (!existsSync(path)) return null;
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
