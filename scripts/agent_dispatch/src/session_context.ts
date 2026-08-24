import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";
import { formatScopedKanbanToolPrompt } from "./dispatch_scoped_tool_prompt.ts";
import type { ParsedClaimResult } from "./mcp_client.ts";
import { wrapWorkerUserRules } from "./user_rule_canary.ts";
import { DISPATCH_SEARCH_POLICY } from "./worker_glob_policy.ts";

export type SessionContext = {
  prompt: string;
  images: ParsedClaimResult["images"];
  attachmentPaths: string[];
  tempDir: string;
  cleanup(): void;
};

export function readBatchArchitecture(cwd: string): string {
  const path = join(cwd, "docs", "Architecture.md");
  if (!existsSync(path)) return "This repository does not provide docs/Architecture.md.";
  return readFileSync(path, "utf8");
}

export function createSessionContext(options: {
  basePrompt: string;
  architecture: string;
  userRules?: string;
  claim: ParsedClaimResult;
  requireTests?: boolean;
  tempRoot?: string;
}): SessionContext {
  const tempDir = mkdtempSync(
    join(options.tempRoot ?? tmpdir(), "kanban-agent-session-"),
  );
  const attachmentPaths: string[] = [];
  const payload = structuredClone(options.claim.payload);
  const fileAttachments = Array.isArray(payload.fileAttachments)
    ? payload.fileAttachments
    : [];

  for (let index = 0; index < fileAttachments.length; index += 1) {
    const raw = fileAttachments[index];
    if (!isRecord(raw)) continue;
    const content = typeof raw.contentBase64 === "string"
      ? raw.contentBase64
      : "";
    delete raw.contentBase64;
    if (!content || raw.included === false) continue;
    const fileName = safeFileName(
      typeof raw.fileName === "string" ? raw.fileName : `attachment-${index}.bin`,
      `attachment-${index}.bin`,
    );
    const path = uniquePath(tempDir, `${index + 1}-${fileName}`);
    writeFileSync(path, Buffer.from(content, "base64"));
    raw.absolutePath = path;
    attachmentPaths.push(path);
  }

  const imagePaths: string[] = [];
  for (let index = 0; index < options.claim.images.length; index += 1) {
    const image = options.claim.images[index]!;
    const path = join(
      tempDir,
      `image-${index + 1}.${extensionForMime(image.mimeType)}`,
    );
    writeFileSync(path, Buffer.from(image.data, "base64"));
    imagePaths.push(path);
  }

  const prompt = [
    options.basePrompt.trim(),
    "",
    "# Worker-injected context for this round",
    "",
    "This round's card is already claimed. The context below is the only task scope; do not read the Skill again or claim another card.",
    "",
    "Card type is decided only by JSON `cardKind` and `labels`: `consultation` is a consultation card, otherwise it is an implementation card. Without a consultation label, even if the title looks like a question and there is no checklist, finish it as an implementation card and call `ready_to_submit`. Do not reclassify it yourself.",
    "",
    DISPATCH_SEARCH_POLICY.trim(),
    "",
    "## Card context (JSON)",
    "",
    "```json",
    JSON.stringify(payload, null, 2),
    "```",
    "",
    formatScopedKanbanToolPrompt(
      cardIdFromPayload(payload),
      options.requireTests !== false,
    ),
    "",
    "## Temporary attachment absolute paths",
    "",
    ...(attachmentPaths.length === 0
      ? ["- No file attachments"]
      : attachmentPaths.map((path) => `- File: ${path}`)),
    ...(imagePaths.length === 0
      ? ["- No temporary image paths"]
      : imagePaths.map((path) => `- Image: ${path}`)),
    "",
    "These paths are in the system temporary session directory and are valid only for this round; do not copy them into the repository.",
    "",
    "## Full user Rules",
    "",
    wrapWorkerUserRules(options.userRules ?? ""),
    "",
    "## Cached docs/Architecture.md",
    "",
    options.architecture.trim(),
    "",
    "The text above already satisfies the user-rule / AGENTS.md requirement to read Architecture.md before development. Do not open that file again. ADRs, docs/Systems, and CONTEXT.md may still be read when needed.",
  ].join("\n");

  return {
    prompt,
    images: options.claim.images,
    attachmentPaths: [...attachmentPaths, ...imagePaths],
    tempDir,
    cleanup: () => {
      rmSync(tempDir, { recursive: true, force: true });
    },
  };
}

function cardIdFromPayload(payload: Record<string, unknown>): string {
  const value = payload.cardId;
  return typeof value === "string" ? value.trim() : "";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function safeFileName(value: string, fallback: string): string {
  const normalized = value
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_")
    .replace(/[. ]+$/g, "")
    .trim();
  return normalized || fallback;
}

function uniquePath(root: string, fileName: string): string {
  const path = join(root, fileName);
  if (!isAbsolute(path)) throw new Error("Temporary attachment path is not absolute");
  return path;
}

function extensionForMime(mimeType: string): string {
  switch (mimeType.toLowerCase()) {
    case "image/png":
      return "png";
    case "image/gif":
      return "gif";
    case "image/webp":
      return "webp";
    default:
      return "jpg";
  }
}
