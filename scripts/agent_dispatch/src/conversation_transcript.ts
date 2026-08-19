import type { ConversationTranscriptMessage } from "./assistant_text.ts";

const INJECTED_PROMPT_MARKERS = [
  "# Worker 注入的本轮上下文",
  "KANBAN_WORKER_USER_RULES_BEGIN",
  "# Skill 正文",
  "看板 MCP 收尾工具",
];

export function isInjectedWorkerPrompt(text: string): boolean {
  return INJECTED_PROMPT_MARKERS.some((marker) => text.includes(marker));
}

export function buildConversationTranscript(options: {
  sessionUser: string;
  live?: readonly ConversationTranscriptMessage[];
  fromTurns?: readonly ConversationTranscriptMessage[];
  trailingAssistant?: string;
}): ConversationTranscriptMessage[] {
  const out: ConversationTranscriptMessage[] = [];
  const sessionUser = options.sessionUser.trim();
  if (sessionUser) pushMessage(out, { role: "user", text: sessionUser });

  const live = (options.live ?? []).filter((item) => !isNoiseUser(item, sessionUser));
  const fromTurns = (options.fromTurns ?? []).filter(
    (item) => !isNoiseUser(item, sessionUser),
  );
  const pendingAssistants = fromTurns
    .filter((item) => item.role === "assistant")
    .map((item) => item.text.trim())
    .filter(Boolean);

  const timeline = live.length > 0 ? live : fromTurns;
  for (const message of timeline) {
    if (message.role === "user") {
      pushMessage(out, message);
      continue;
    }
    const liveText = message.text.trim();
    const index = pendingAssistants.findIndex((text) => relatedAssistant(text, liveText));
    if (index >= 0) {
      const snapshot = pendingAssistants.splice(index, 1)[0] ?? liveText;
      pushMessage(out, {
        role: "assistant",
        text: longerText(snapshot, liveText),
      });
      continue;
    }
    pushMessage(out, message);
  }

  for (const text of pendingAssistants) {
    pushMessage(out, { role: "assistant", text });
  }
  if (options.trailingAssistant) {
    pushMessage(out, {
      role: "assistant",
      text: options.trailingAssistant,
    });
  }
  return out;
}

function isNoiseUser(
  message: ConversationTranscriptMessage,
  sessionUser: string,
): boolean {
  if (message.role !== "user") return false;
  const text = message.text.trim();
  if (!text) return true;
  if (sessionUser && text === sessionUser) return true;
  return isInjectedWorkerPrompt(text);
}

function relatedAssistant(left: string, right: string): boolean {
  return left === right || left.startsWith(right) || right.startsWith(left);
}

function longerText(left: string, right: string): string {
  return left.length >= right.length ? left : right;
}

function pushMessage(
  out: ConversationTranscriptMessage[],
  message: ConversationTranscriptMessage,
): void {
  const text = message.text.trim();
  if (!text) return;
  const last = out[out.length - 1];
  if (last && last.role === message.role && last.text === text) return;
  if (last && last.role === "assistant" && message.role === "assistant") {
    if (text.startsWith(last.text)) {
      last.text = text;
      return;
    }
    if (last.text.startsWith(text)) return;
  }
  if (
    message.role === "user" &&
    out.some((item) => item.role === "user" && item.text === text)
  ) {
    return;
  }
  out.push({ role: message.role, text });
}
