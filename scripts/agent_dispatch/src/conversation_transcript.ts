import type { ConversationTranscriptMessage } from "./assistant_text.ts";

/** Current English headings written into the Worker prompt. */
const INJECTED_PROMPT_MARKERS = [
  "# Worker-injected context for this round",
  "# Skill body",
  "# This invocation",
  "KANBAN_WORKER_USER_RULES_BEGIN",
  "Kanban MCP completion tools",
];

/**
 * Chinese headings from prompts written before the English translation.
 * Used only to strip historical user turns; never injected as prompt copy.
 */
const LEGACY_INJECTED_PROMPT_MARKERS = [
  "# Worker \u6CE8\u5165\u7684\u672C\u8F6E\u4E0A\u4E0B\u6587",
  "# Skill \u6B63\u6587",
  "# \u672C\u6B21\u8C03\u7528",
  "\u770B\u677F MCP \u6536\u5C3E\u5DE5\u5177",
];

export function isInjectedWorkerPrompt(text: string): boolean {
  return INJECTED_PROMPT_MARKERS.concat(LEGACY_INJECTED_PROMPT_MARKERS).some(
    (marker) => text.includes(marker),
  );
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
  const pending = fromTurns
    .filter((item) => item.role !== "user")
    .map((item) => ({ role: item.role, text: item.text.trim() }))
    .filter((item) => item.text.length > 0);

  const timeline = live.length > 0 ? live : fromTurns;
  for (const message of timeline) {
    if (message.role === "user") {
      pushMessage(out, message);
      continue;
    }
    const liveText = message.text.trim();
    const index = pending.findIndex(
      (item) => item.role === message.role && relatedText(item.text, liveText),
    );
    if (index >= 0) {
      const snapshot = pending.splice(index, 1)[0];
      pushMessage(out, {
        role: message.role,
        text: longerText(snapshot?.text ?? liveText, liveText),
      });
      continue;
    }
    pushMessage(out, message);
  }

  for (const item of pending) {
    pushMessage(out, item);
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

function relatedText(left: string, right: string): boolean {
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
  if (last && last.role === message.role && message.role !== "user") {
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
