/** scoped kanban MCP tool names, alphabetical to match the listTools gate. */
export const DISPATCH_SCOPED_TOOL_NAMES = [
  "block_card",
  "ready_to_submit",
  "submit_consultation",
] as const;

/** Injected into the Worker prompt: completion-tool schema so the model does not call GetMcpTools. */
export function formatScopedKanbanToolPrompt(
  cardId: string,
  requireTests = true,
): string {
  const id = cardId.trim() || "<injected cardId>";
  return [
    "## Kanban MCP completion tools (schema already injected)",
    "",
    "scoped `kanbanMCP` registers only the three tools below. Do not call `GetMcpTools`, `tools/list`, or fetch any other kanban tool catalog.",
            "Cursor: call `CallMcpTool` directly; Codex: call the same-named MCP tool directly. `cardId` must be the injected value.",
            requireTests
              ? "Do not put ready_to_submit in the same parallel tool batch as Shell (especially tests). Wait until the test command returns exitCode=0, then call ready_to_submit in a separate turn."
              : "This card is configured not to require tests: do not run automated tests; after implementation, pass manualVerificationReason=This card has no test switch enabled to ready_to_submit.",
            "As soon as ready_to_submit / submit_consultation / block_card returns success, stop all tools; the Worker will end this session. Do not search, edit, or redo the task again.",
            "Card type is decided only by injected JSON cardKind / labels: it is a consultation card only when cardKind=consultation or labels contain consultation; otherwise it is always an implementation card. Do not reclassify from whether the title or notes look like a question.",
            "The Shell working_directory must match relative paths in the command: when cwd is already app, do not write app/lib. A flutter test / dart test that exits immediately must not count as passing.",
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
              completedChecklistIds: "checklist ids completed this round; [] if none",
              completedFeedbackIds: "feedback ids completed this round; [] if none",
              manualVerificationReason: "pass only when automatic verification is impossible",
              gitRevertCommit: "pass a 7–64 character hash only when workItems explicitly require revert",
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
              responseMarkdown: "consultation response Markdown",
            },
          },
          block_card: {
            required: ["cardId"],
            properties: { reason: "block reason" },
            example: { cardId: id, reason: "why completion is impossible" },
          },
        },
      },
      null,
      2,
    ),
    "```",
  ].join("\n");
}
