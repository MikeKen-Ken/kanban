import assert from "node:assert/strict";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { isAbsolute, join } from "node:path";
import { tmpdir } from "node:os";
import { describe, it } from "node:test";
import type { CallToolResult } from "@modelcontextprotocol/client";
import { createSessionContext } from "./session_context.ts";
import {
  WORKER_USER_RULES_BEGIN,
  WORKER_USER_RULES_END,
} from "./user_rule_canary.ts";

describe("session_context", () => {
  it("\u9644\u4EF6\u53EA\u5199\u7CFB\u7EDF\u4E34\u65F6\u76EE\u5F55\u4E14 prompt \u4E0D\u542B base64", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-context-test-"));
    const base64 = Buffer.from("\u9644\u4EF6\u5185\u5BB9").toString("base64");
    const context = createSessionContext({
      basePrompt: "Do the task",
      architecture: "# Architecture",
      userRules: "# All user rules\n\nAlways respond in English.",
      tempRoot: root,
      claim: {
        payload: {
          cardId: "card-a",
          workItems: [{ id: "item-a", text: "\u5B8C\u6210 A" }],
          fileAttachments: [{
            fileName: "\u8BF4\u660E.txt",
            included: true,
            contentBase64: base64,
          }],
        },
        images: [{
          data: Buffer.from("image").toString("base64"),
          mimeType: "image/png",
        }],
        raw: { content: [] } as unknown as CallToolResult,
      },
    });
    try {
      assert.equal(context.attachmentPaths.length, 2);
      assert.ok(context.attachmentPaths.every(isAbsolute));
      assert.ok(context.attachmentPaths.every(existsSync));
      assert.equal(context.prompt.includes(base64), false);
      assert.match(context.prompt, /\u5B8C\u6210 A/);
      assert.match(context.prompt, /Cached docs\/Architecture\.md/);
      assert.match(context.prompt, /Full user Rules/);
      assert.equal(
        context.prompt.split(WORKER_USER_RULES_BEGIN).length - 1,
        1,
      );
      assert.equal(context.prompt.split(WORKER_USER_RULES_END).length - 1, 1);
      assert.match(context.prompt, /Always respond in English/);
      assert.match(context.prompt, /Kanban MCP completion tools/);
      assert.match(context.prompt, /GetMcpTools/);
      assert.match(context.prompt, /card-a/);
      assert.match(context.prompt, /read Architecture.md before development/);
      assert.match(context.prompt, /MUST NOT unbounded-glob the repository root/);
      assert.match(context.prompt, /\.svn/);
      assert.match(context.prompt, /currently selected repository's directory layout/);
      assert.equal(context.prompt.includes('features/kanban'), false);
      assert.equal(context.prompt.includes('agent_dispatch/'), false);
      assert.match(context.prompt, /cardKind/);
      assert.match(context.prompt, /always an implementation card|otherwise it is an implementation card/);
      assert.equal(
        readFileSync(context.attachmentPaths[0]!, "utf8"),
        "\u9644\u4EF6\u5185\u5BB9",
      );
    } finally {
      context.cleanup();
      assert.equal(existsSync(context.tempDir), false);
      rmSync(root, { recursive: true, force: true });
    }
  });
});
