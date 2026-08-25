import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ParsedClaimResult } from "./mcp_client.ts";

export type SessionContext = {
  prompt: string;
  images: ParsedClaimResult["images"];
  attachmentPaths: string[];
  tempDir: string;
  cleanup(): void;
};

export function createSessionContext(options: {
  basePrompt: string;
  claim: ParsedClaimResult;
  tempRoot?: string;
}): SessionContext {
  const tempDir = mkdtempSync(
    join(options.tempRoot ?? tmpdir(), "kanban-agent-session-"),
  );
  return {
    prompt: options.basePrompt.trim(),
    images: [],
    attachmentPaths: [],
    tempDir,
    cleanup: () => {
      rmSync(tempDir, { recursive: true, force: true });
    },
  };
}
