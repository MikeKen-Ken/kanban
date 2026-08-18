/** 项目 MCP 标签 → 用户/项目 mcp.json 中的服务器名（大小写按配置原文保留）。 */
export const MCP_LABEL_SERVERS: Record<string, readonly string[]> = {
  aseprite: ["aseprite"],
  "chrome-devtools": ["chrome-devtools"],
  chrome: ["chrome-devtools"],
  hub: ["hubMCP"],
  hubMCP: ["hubMCP"],
  tavily: ["tavily"],
  unity: ["unitymcp", "unityMCP"],
  cocos: ["cocos-creator"],
  node_repl: ["node_repl"],
};

export function parseProjectMcpTags(payload: Record<string, unknown>): string[] {
  const raw = payload.projectMcpTags;
  if (!Array.isArray(raw)) return [];
  const result: string[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    if (typeof item !== "string") continue;
    const label = item.trim();
    if (!label || seen.has(label)) continue;
    seen.add(label);
    result.push(label);
  }
  return result;
}

export function allowedMcpServerNames(labels: readonly string[]): Set<string> {
  const allowed = new Set<string>();
  for (const raw of labels) {
    const key = raw.trim();
    if (!key) continue;
    const mapped = MCP_LABEL_SERVERS[key] ?? MCP_LABEL_SERVERS[key.toLowerCase()];
    if (mapped) {
      for (const name of mapped) allowed.add(name);
      continue;
    }
    allowed.add(key);
  }
  return allowed;
}

export function mcpServerNameAllowed(
  serverName: string,
  allowed: ReadonlySet<string>,
): boolean {
  const name = serverName.trim();
  if (!name) return false;
  if (allowed.has(name)) return true;
  const lower = name.toLowerCase();
  for (const item of allowed) {
    if (item.toLowerCase() === lower) return true;
  }
  return false;
}

export function filterRecordByMcpAllowlist<T>(
  servers: Record<string, T>,
  labels: readonly string[],
): Record<string, T> {
  const allowed = allowedMcpServerNames(labels);
  if (allowed.size === 0) return {};
  const result: Record<string, T> = {};
  for (const [name, value] of Object.entries(servers)) {
    if (mcpServerNameAllowed(name, allowed)) result[name] = value;
  }
  return result;
}
