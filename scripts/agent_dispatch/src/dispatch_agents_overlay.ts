/** 只覆盖「必须再打开 Architecture.md」；ADR / Systems / CONTEXT 仍按用户原文。 */
export const DISPATCH_ARCHITECTURE_OVERRIDE = `# 本会话覆盖（仅看板 Agent 调度）

Worker 已注入目标仓库 \`docs/Architecture.md\` 全文。用户规则 / \`AGENTS.md\` 里的「开发前必读 Architecture.md」在本轮视为已满足。
禁止再搜索、glob、grep 或读取 \`docs/Architecture.md\`。ADR、\`docs/Systems/\`、\`CONTEXT.md\` 仍按原文，需要时再读。
`;

export function applyDispatchArchitectureOverride(source: string): string {
  const body = rewriteArchitectureFileReads(source.replaceAll("\r\n", "\n").trim());
  return `${DISPATCH_ARCHITECTURE_OVERRIDE.trim()}\n\n${body}`.trim() + "\n";
}

function rewriteArchitectureFileReads(source: string): string {
  if (!source) return "";
  return source
    .split("\n")
    .filter((line) => !isArchitectureFileReadBullet(line))
    .join("\n")
    .replace(
      /动手写代码[^\n]*MUST 先阅读：/,
      "动手写代码、改模块边界或设计方案前，`docs/Architecture.md` 已由 Worker 注入，视为已读；禁止再打开该文件。",
    )
    .replace(
      /MUST NOT 在未读 `Architecture\.md`（若存在）的情况下/,
      "MUST NOT 在未遵守已注入 Architecture.md 的情况下",
    );
}

function isArchitectureFileReadBullet(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed.startsWith("-") && !trimmed.startsWith("*")) return false;
  return trimmed.includes("docs/Architecture.md");
}
