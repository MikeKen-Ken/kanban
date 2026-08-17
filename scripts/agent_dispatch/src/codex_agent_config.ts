const KANBAN_TABLE = "mcp_servers.kanbanMCP";

export function isKanbanMcpTable(name: string): boolean {
  const table = name.trim();
  return table === KANBAN_TABLE || table.startsWith(`${KANBAN_TABLE}.`);
}

/** 去掉用户 config 里完整看板 MCP 及其子表，避免连上常驻工具目录。 */
export function stripKanbanMcpTables(source: string): string {
  const matches = [...source.matchAll(/^\[([^\]]+)\]/gm)];
  if (matches.length === 0) return source;
  const firstIndex = matches[0]?.index ?? 0;
  let result = source.slice(0, firstIndex);
  for (let index = 0; index < matches.length; index += 1) {
    const match = matches[index]!;
    const name = match[1] ?? "";
    const start = match.index ?? 0;
    const end = matches[index + 1]?.index ?? source.length;
    if (isKanbanMcpTable(name)) continue;
    result += source.slice(start, end);
  }
  return collapseBlankLines(result);
}

export function ensureCodexRmcpClient(source: string): string {
  if (/^\s*rmcp_client\s*=\s*true\s*$/m.test(source)) return source;
  const features = /^\[features\]\s*$/m.exec(source);
  if (features == null || features.index == null) {
    const trimmed = source.trimEnd();
    const block = "[features]\nrmcp_client = true\n";
    if (!trimmed) return block;
    return `${trimmed}\n\n${block}`;
  }
  const insertAt = features.index + features[0].length;
  return `${source.slice(0, insertAt)}\nrmcp_client = true${source.slice(insertAt)}`;
}

export function buildCodexAgentConfigToml(
  mcpUrl: string,
  userConfig = "",
): string {
  const url = mcpUrl.trim();
  const withoutKanban = stripKanbanMcpTables(userConfig);
  const withFeatures = ensureCodexRmcpClient(withoutKanban);
  const block = `[mcp_servers.kanbanMCP]\nurl = "${url}"\n`;
  const trimmed = withFeatures.trimEnd();
  if (!trimmed) {
    return `[features]\nrmcp_client = true\n\n${block}`;
  }
  return `${trimmed}\n\n${block}`;
}

export function listCodexMcpServerNames(toml: string): string[] {
  const names: string[] = [];
  const seen = new Set<string>();
  for (const match of toml.matchAll(/^\[mcp_servers\.([^\].]+)\]/gm)) {
    const name = match[1]?.trim();
    if (!name || seen.has(name)) continue;
    seen.add(name);
    names.push(name);
  }
  return names;
}

function collapseBlankLines(source: string): string {
  return source.replace(/\n{3,}/g, "\n\n").replace(/^\n+/, "").trimEnd();
}
