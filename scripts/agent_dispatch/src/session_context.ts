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
  if (!existsSync(path)) return "仓库未提供 docs/Architecture.md。";
  return readFileSync(path, "utf8");
}

export function createSessionContext(options: {
  basePrompt: string;
  architecture: string;
  userRules?: string;
  claim: ParsedClaimResult;
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
    "# Worker 注入的本轮上下文",
    "",
    "本轮卡片已领取。以下上下文是唯一任务范围；不要再次读取 Skill 或领取其他卡片。",
    "",
    "卡片类型只由 JSON 的 `cardKind` 与 `labels` 决定：`consultation` 为咨询卡，否则为实施卡。未打咨询标签时，即使标题像提问、没有清单，也必须当实施卡做完并 `ready_to_submit`。不要自行改判。",
    "",
    DISPATCH_SEARCH_POLICY.trim(),
    "",
    "## 卡片上下文（JSON）",
    "",
    "```json",
    JSON.stringify(payload, null, 2),
    "```",
    "",
    formatScopedKanbanToolPrompt(cardIdFromPayload(payload)),
    "",
    "## 临时附件绝对路径",
    "",
    ...(attachmentPaths.length === 0
      ? ["- 无文件附件"]
      : attachmentPaths.map((path) => `- 文件：${path}`)),
    ...(imagePaths.length === 0
      ? ["- 无图片临时路径"]
      : imagePaths.map((path) => `- 图片：${path}`)),
    "",
    "这些路径位于系统临时会话目录，只在本轮有效；不要复制到仓库。",
    "",
    "## 完整用户 Rule",
    "",
    wrapWorkerUserRules(options.userRules ?? ""),
    "",
    "## 已缓存的 docs/Architecture.md",
    "",
    options.architecture.trim(),
    "",
    "以上正文已满足用户规则 / AGENTS.md 中的「开发前必读 Architecture.md」。禁止再打开该文件。ADR、docs/Systems、CONTEXT.md 需要时仍可读。",
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
  if (!isAbsolute(path)) throw new Error("临时附件路径不是绝对路径");
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
