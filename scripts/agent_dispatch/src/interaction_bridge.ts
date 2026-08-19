import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
  writeSync,
} from "node:fs";
import { randomUUID } from "node:crypto";
import { join } from "node:path";
import type { SDKCustomTool, SDKJsonValue } from "@cursor/sdk";
import type { ConversationTranscriptMessage } from "./assistant_text.ts";
import type { WorkerCancellation } from "./cancellation.ts";
import type { RoundDispatchJob } from "./types.ts";

export const INTERACTION_EVENT_PREFIX = "@@KANBAN_INTERACTION@@";

export type InteractionEvent = {
  type: "session" | "assistant" | "question" | "user" | "snapshot";
  projectId?: string;
  cardId: string;
  sessionId: string;
  text: string;
  requestId?: string;
  choices?: string[];
  at: string;
};

/** 测试可替换；默认与 Worker 日志一样用 writeSync，避免和日志互相截断 JSON。 */
export const interactionStdio = {
  write(line: string): void {
    writeSync(1, line);
  },
};

export function emitInteractionEvent(
  event: Omit<InteractionEvent, "at">,
): void {
  interactionStdio.write(
    `${INTERACTION_EVENT_PREFIX}${JSON.stringify({
      ...event,
      at: new Date().toISOString(),
    })}\n`,
  );
}

export function sessionStartText(job: RoundDispatchJob): string {
  const items = workItems(job);
  return items.length === 0
    ? "开始处理本卡。"
    : items.map((item) => `- ${item}`).join("\n");
}

export function conversationSnapshotFileName(cardId: string): string {
  return `conversation-snapshot-${cardId.replace(/[^a-zA-Z0-9._-]/g, "_")}.json`;
}

export function writeConversationSnapshot(
  job: RoundDispatchJob,
  messages: readonly ConversationTranscriptMessage[],
): string | undefined {
  const interactionDir = job.interactionDir?.trim();
  if (!interactionDir || messages.length === 0) return undefined;
  mkdirSync(interactionDir, { recursive: true });
  const fileName = conversationSnapshotFileName(job.round.cardId);
  writeFileSync(
    join(interactionDir, fileName),
    `${JSON.stringify({
      cardId: job.round.cardId,
      sessionId: job.round.sessionId,
      projectId: job.projectId,
      messages,
    })}\n`,
    "utf8",
  );
  return fileName;
}

export function emitConversationSnapshot(
  job: RoundDispatchJob,
  messages: readonly ConversationTranscriptMessage[],
): void {
  const fileName = writeConversationSnapshot(job, messages);
  if (!fileName) return;
  emitInteractionEvent({
    type: "snapshot",
    projectId: job.projectId,
    cardId: job.round.cardId,
    sessionId: job.round.sessionId,
    text: fileName,
  });
}

export function emitSessionStart(job: RoundDispatchJob): void {
  emitInteractionEvent({
    type: "session",
    projectId: job.projectId,
    cardId: job.round.cardId,
    sessionId: job.round.sessionId,
    text: sessionStartText(job),
  });
}

export function emitAssistantMessage(
  job: RoundDispatchJob,
  text: string,
): void {
  const normalized = text.trim();
  if (!normalized) return;
  emitInteractionEvent({
    type: "assistant",
    projectId: job.projectId,
    cardId: job.round.cardId,
    sessionId: job.round.sessionId,
    text: normalized,
  });
}

export function createAskUserTool(
  job: RoundDispatchJob,
  cancellation?: WorkerCancellation,
  onUserReply?: (text: string) => void,
): SDKCustomTool | undefined {
  const interactionDir = job.interactionDir?.trim();
  if (!interactionDir) return undefined;
  mkdirSync(interactionDir, { recursive: true });
  return {
    description:
      "需要用户确认、补充需求或选择方案时调用。有互斥方案时传入 choices，看板会弹出选项菜单；工具会暂停当前卡片，直到用户回复。",
    inputSchema: {
      type: "object",
      properties: {
        question: {
          type: "string",
          description: "向用户提出的完整问题，使用简体中文。",
        },
        choices: {
          type: "array",
          description:
            "2 到 4 个互斥选项。有明确方案时必须提供，看板会在最近运行界面弹出选项菜单供用户点选；不要只在正文里口头列出选项。",
          items: { type: "string" },
          minItems: 2,
          maxItems: 4,
        },
      },
      required: ["question"],
      additionalProperties: false,
    },
    execute: async (args) => {
      const question = stringArg(args.question);
      if (!question) {
        return { content: [{ type: "text", text: "问题不能为空" }], isError: true };
      }
      const explicit = stringListArg(args.choices);
      const choices =
        explicit.length > 0 ? explicit : inferChoicesFromQuestion(question);
      const requestId = randomUUID();
      const replyPath = join(interactionDir, `${requestId}.reply.json`);
      emitInteractionEvent({
        type: "question",
        projectId: job.projectId,
        cardId: job.round.cardId,
        sessionId: job.round.sessionId,
        requestId,
        text: question,
        ...(choices.length > 0 ? { choices } : {}),
      });
      const answer = await waitForReply(replyPath, cancellation);
      if (answer && answer !== "用户已终止当前会话。") {
        onUserReply?.(answer);
      }
      return answer;
    },
  };
}

async function waitForReply(
  replyPath: string,
  cancellation?: WorkerCancellation,
): Promise<string> {
  while (true) {
    if (cancellation?.isCancelled || cancellation?.isSkipRequested) {
      return "用户已终止当前会话。";
    }
    if (existsSync(replyPath)) {
      try {
        const decoded = JSON.parse(readFileSync(replyPath, "utf8")) as {
          text?: unknown;
        };
        const text = String(decoded.text ?? "").trim();
        if (text) return text;
      } catch {
        // 写入尚未完成时等待下一轮。
      } finally {
        rmSync(replyPath, { force: true });
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}

function stringArg(value: SDKJsonValue | undefined): string {
  return typeof value === "string" ? value.trim() : "";
}

function stringListArg(value: SDKJsonValue | undefined): string[] {
  if (!Array.isArray(value)) return [];
  const choices: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const text = item.trim();
    if (!text || choices.includes(text)) continue;
    choices.push(text);
    if (choices.length >= 4) break;
  }
  return choices.length >= 2 ? choices : [];
}

const choiceLinePattern = /^\s*(?:\d+[\.、\)]|[-*•])\s+(.+)$/;

function inferChoicesFromQuestion(question: string): string[] {
  const items: string[] = [];
  for (const line of question.split(/\r?\n/)) {
    const match = choiceLinePattern.exec(line);
    const text = match?.[1]?.trim() ?? "";
    if (!text || items.includes(text)) continue;
    items.push(text);
    if (items.length >= 4) break;
  }
  return items.length >= 2 ? items : [];
}

function workItems(job: RoundDispatchJob): string[] {
  const raw = job.round.cardContext?.workItems;
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      return [];
    }
    const text = String((item as Record<string, unknown>).text ?? "").trim();
    return text ? [text] : [];
  });
}
