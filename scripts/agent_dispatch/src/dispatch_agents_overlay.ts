/** Override only "must open Architecture.md again"; ADR / Systems / CONTEXT still follow the user's original text. */
export const DISPATCH_ARCHITECTURE_OVERRIDE = `# This-session override (kanban Agent dispatch only)

The Worker has already injected the full target-repository \`docs/Architecture.md\`. The user-rule / \`AGENTS.md\` requirement to read Architecture.md before development is treated as satisfied for this round.
Do not search, glob, grep, or read \`docs/Architecture.md\` again. ADRs, \`docs/Systems/\`, and \`CONTEXT.md\` still follow the original text and may be read when needed.
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
      "Before writing code, changing module boundaries, or designing a solution, `docs/Architecture.md` has already been injected by the Worker and counts as read; do not open that file again.",
    )
    .replace(
      /Before writing code[^\n]*MUST (?:first )?read:/,
      "Before writing code, changing module boundaries, or designing a solution, `docs/Architecture.md` has already been injected by the Worker and counts as read; do not open that file again.",
    )
    .replace(
      /MUST NOT 在未读 `Architecture\.md`（若存在）的情况下/,
      "MUST NOT without following the injected Architecture.md",
    )
    .replace(
      /MUST NOT (?:add new top-level directories or cross-layer dependencies )?without reading `Architecture\.md`(?: \(if it exists\))?/,
      "MUST NOT without following the injected Architecture.md",
    );
}

function isArchitectureFileReadBullet(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed.startsWith("-") && !trimmed.startsWith("*")) return false;
  return trimmed.includes("docs/Architecture.md");
}
