import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { describe, it } from "node:test";
import type { CallToolResult } from "@modelcontextprotocol/client";
import { createSessionContext } from "./session_context.ts";

describe("session_context", () => {
  it("does not inject claimed card data into the prompt", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-context-test-"));
    const context = createSessionContext({
      basePrompt: "Use the Skill",
      tempRoot: root,
      claim: {
        payload: { cardId: "card-a", title: "secret task" },
        images: [],
        raw: { content: [] } as unknown as CallToolResult,
      },
    });
    try {
      assert.equal(context.prompt, "Use the Skill");
      assert.equal(context.prompt.includes("card-a"), false);
      assert.equal(context.attachmentPaths.length, 0);
      assert.deepEqual(context.images, []);
    } finally {
      context.cleanup();
      assert.equal(existsSync(context.tempDir), false);
      rmSync(root, { recursive: true, force: true });
    }
  });
});
