/** scoped 看板 MCP 工具名，按字母序与 listTools 门禁对齐。 */
export const DISPATCH_SCOPED_TOOL_NAMES = [
  "block_card",
  "ready_to_submit",
  "submit_consultation",
] as const;

/** 注入到 Worker prompt：收尾工具 schema，避免模型再 GetMcpTools。 */
export function formatScopedKanbanToolPrompt(cardId: string): string {
  const id = cardId.trim() || "<注入的 cardId>";
  return [
    "## 看板 MCP 收尾工具（已注入 schema）",
    "",
    "scoped `kanbanMCP` 只注册下面三个工具。禁止 `GetMcpTools`、`tools/list` 或拉取其它看板工具目录。",
            "Cursor：直接 `CallMcpTool`；Codex：直接调用同名 MCP 工具。`cardId` 必须是注入值。",
            "禁止把 ready_to_submit 与 Shell（尤其是测试）放在同一批并行工具里。必须等测试命令返回 exitCode=0 之后，再单独调用 ready_to_submit。",
            "Shell 的 working_directory 必须与命令里的相对路径一致：cwd 已是 app 时不要再写 app/lib。flutter test / dart test 秒退不得视为通过。",
    "",
    "```json",
    JSON.stringify(
      {
        server: "kanbanMCP",
        tools: {
          ready_to_submit: {
            required: [
              "cardId",
              "completedChecklistIds",
              "completedFeedbackIds",
            ],
            properties: {
              cardId: id,
              completedChecklistIds: "本轮完成的 checklist id；无则 []",
              completedFeedbackIds: "本轮完成的 feedback id；无则 []",
              manualVerificationReason: "无法自动验证时才传",
              gitRevertCommit: "仅当 workItems 明确要求 revert 时传 7–64 位哈希",
            },
            example: {
              cardId: id,
              completedChecklistIds: [],
              completedFeedbackIds: [],
            },
          },
          submit_consultation: {
            required: ["cardId", "responseMarkdown"],
            example: {
              cardId: id,
              responseMarkdown: "咨询答复 Markdown",
            },
          },
          block_card: {
            required: ["cardId"],
            properties: { reason: "阻塞原因" },
            example: { cardId: id, reason: "无法完成的原因" },
          },
        },
      },
      null,
      2,
    ),
    "```",
  ].join("\n");
}
