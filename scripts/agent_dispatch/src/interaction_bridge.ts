import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeSync,
} from "node:fs";
import { randomUUID } from "node:crypto";
import { join } from "node:path";
import type { SDKCustomTool, SDKJsonValue } from "@cursor/sdk";
import type { WorkerCancellation } from "./cancellation.ts";
import type { RoundDispatchJob } from "./types.ts";

export const INTERACTION_EVENT_PREFIX = "@@KANBAN_INTERACTION@@";

export type InteractionEvent = {
  type: "session" | "assistant" | "question";
  projectId?: string;
  cardId: string;
  sessionId: string;
  text: string;
  requestId?: string;
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

export function emitSessionStart(job: RoundDispatchJob): void {
  const items = workItems(job);
  const text = items.length === 0
    ? "开始处理本卡。"
    : items.map((item) => `- ${item}`).join("\n");
  emitInteractionEvent({
    type: "session",
    projectId: job.projectId,
    cardId: job.round.cardId,
    sessionId: job.round.sessionId,
    text,
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
): SDKCustomTool | undefined {
  const interactionDir = job.interactionDir?.trim();
  if (!interactionDir) return undefined;
  mkdirSync(interactionDir, { recursive: true });
  return {
    description:
      "需要用户确认、补充需求或选择方案时调用。工具会暂停当前卡片，直到用户在看板对话中回复。",
    inputSchema: {
      type: "object",
      properties: {
        question: {
          type: "string",
          description: "向用户提出的完整问题，使用简体中文。",
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
      const requestId = randomUUID();
      const replyPath = join(interactionDir, `${requestId}.reply.json`);
      emitInteractionEvent({
        type: "question",
        projectId: job.projectId,
        cardId: job.round.cardId,
        sessionId: job.round.sessionId,
        requestId,
        text: question,
      });
      const answer = await waitForReply(replyPath, cancellation);
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
