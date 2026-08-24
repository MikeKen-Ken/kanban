/** Extract user-facing assistant text from Cursor steps or Codex events. */
export function extractAssistantText(value: unknown): string {
  const chunks: string[] = [];
  collectText(value, chunks, 0);
  return chunks.join("").trim();
}

export function extractCursorAssistantStepText(step: unknown): string {
  const record = asRecord(step);
  if (!record) return "";
  const type = String(record.type ?? "");
  if (type && type !== "assistantMessage" && type !== "assistant") return "";
  return extractAssistantText(record.message ?? record);
}

export function extractCursorThinkingStepText(step: unknown): string {
  const record = asRecord(step);
  if (!record) return "";
  const type = String(record.type ?? "");
  const message = asRecord(record.message) ?? record;
  if (
    type &&
    type !== "thinkingMessage" &&
    type !== "thinking" &&
    type !== "reasoning"
  ) {
    if (
      typeof message.thinking !== "string" &&
      typeof message.thinkingDurationMs !== "number"
    ) {
      return "";
    }
  }
  return extractThinkingText(record.message ?? record);
}

export type ConversationTranscriptRole = "user" | "assistant" | "thinking";

export type ConversationTranscriptMessage = {
  role: ConversationTranscriptRole;
  text: string;
};

export function extractCodexAssistantEventText(event: unknown): string {
  const message = extractCodexTranscriptMessage(event);
  return message?.role === "assistant" ? message.text : "";
}

export function extractCodexTranscriptMessage(
  event: unknown,
): ConversationTranscriptMessage | undefined {
  const record = asRecord(event);
  if (!record) return undefined;
  const type = String(record.type ?? "");
  const item = asRecord(record.item) ?? {};
  const itemType = String(item.type ?? item.item_type ?? "");
  const role = String(item.role ?? "");
  if (itemType === "reasoning" || itemType === "thinking") {
    if (type !== "item.completed" && type !== "item.updated") return undefined;
    const thinking = extractThinkingText(item);
    return thinking ? { role: "thinking", text: thinking } : undefined;
  }
  if (type !== "item.completed") return undefined;
  if (
    itemType === "user_message" ||
    itemType === "user" ||
    (itemType === "message" && role === "user")
  ) {
    const text = extractAssistantText(item);
    return text ? { role: "user", text } : undefined;
  }
  if (
    itemType === "agent_message" ||
    itemType === "assistant_message" ||
    (itemType === "message" && (role === "assistant" || role === "agent"))
  ) {
    const text = extractAssistantText(item);
    return text ? { role: "assistant", text } : undefined;
  }
  return undefined;
}

export function extractConversationMessages(
  turns: unknown,
): ConversationTranscriptMessage[] {
  const messages: ConversationTranscriptMessage[] = [];
  if (!Array.isArray(turns)) return messages;
  for (const turn of turns) {
    const record = asRecord(turn);
    if (!record) continue;
    const inner = asRecord(record.turn) ?? record;
    const userText = extractUserText(inner.userMessage ?? record.userMessage);
    if (userText) messages.push({ role: "user", text: userText });
    const steps = inner.steps ?? record.steps;
    if (!Array.isArray(steps)) continue;
    for (const step of steps) {
      const thinking = extractCursorThinkingStepText(step);
      if (thinking) {
        messages.push({ role: "thinking", text: thinking });
        continue;
      }
      const assistant = extractCursorAssistantStepText(step);
      if (assistant) messages.push({ role: "assistant", text: assistant });
    }
  }
  return messages;
}

function extractThinkingText(value: unknown): string {
  if (typeof value === "string") return value.trim();
  const record = asRecord(value);
  if (!record) return "";
  for (const key of ["thinking", "text"] as const) {
    const field = record[key];
    if (typeof field === "string" && field.trim()) return field.trim();
  }
  const content = record.content;
  if (Array.isArray(content)) {
    const parts = content
      .map((item) => {
        if (typeof item === "string") return item.trim();
        const inner = asRecord(item);
        if (!inner) return "";
        const innerType = String(inner.type ?? "");
        if (
          innerType &&
          innerType !== "thinking" &&
          innerType !== "reasoning" &&
          innerType !== "reasoning_text" &&
          innerType !== "text"
        ) {
          return "";
        }
        return extractThinkingText(inner);
      })
      .filter((part) => part.length > 0);
    if (parts.length > 0) return parts.join("\n").trim();
  }
  if (typeof content === "string" && content.trim()) return content.trim();
  return extractAssistantText(record);
}

function extractUserText(value: unknown): string {
  if (typeof value === "string") return value.trim();
  const record = asRecord(value);
  if (!record) return "";
  if (typeof record.text === "string" && record.text.trim()) {
    return record.text.trim();
  }
  return extractAssistantText(record);
}

function collectText(
  value: unknown,
  chunks: string[],
  depth: number,
): void {
  if (depth > 6 || value == null) return;
  if (typeof value === "string") {
    if (value.trim()) chunks.push(value);
    return;
  }
  if (typeof value !== "object") return;
  if (Array.isArray(value)) {
    for (const item of value) collectText(item, chunks, depth + 1);
    return;
  }
  const record = value as Record<string, unknown>;
  const type = String(record.type ?? "");
  if (type === "tool_use" || type === "tool-use" || type === "toolCall") return;
  if (typeof record.text === "string" && record.text.trim()) {
    chunks.push(record.text);
    return;
  }
  if (typeof record.thinking === "string" && type === "thinking") return;
  if (record.content !== undefined) {
    collectText(record.content, chunks, depth + 1);
    return;
  }
  if (record.parts !== undefined) {
    collectText(record.parts, chunks, depth + 1);
    return;
  }
  if (record.message !== undefined) {
    collectText(record.message, chunks, depth + 1);
  }
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}
