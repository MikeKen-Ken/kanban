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
  it("附件只写系统临时目录且 prompt 不含 base64", () => {
    const root = mkdtempSync(join(tmpdir(), "kanban-context-test-"));
    const base64 = Buffer.from("附件内容").toString("base64");
    const context = createSessionContext({
      basePrompt: "执行任务",
      architecture: "# 架构",
      userRules: "# 所有用户规则\n\n必须使用简体中文。",
      tempRoot: root,
      claim: {
        payload: {
          cardId: "card-a",
          workItems: [{ id: "item-a", text: "完成 A" }],
          fileAttachments: [{
            fileName: "说明.txt",
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
      assert.match(context.prompt, /完成 A/);
      assert.match(context.prompt, /已缓存的 docs\/Architecture\.md/);
      assert.match(context.prompt, /完整用户 Rule/);
      assert.equal(
        context.prompt.split(WORKER_USER_RULES_BEGIN).length - 1,
        1,
      );
      assert.equal(context.prompt.split(WORKER_USER_RULES_END).length - 1, 1);
      assert.match(context.prompt, /必须使用简体中文/);
      assert.match(context.prompt, /看板 MCP 收尾工具/);
      assert.match(context.prompt, /GetMcpTools/);
      assert.match(context.prompt, /card-a/);
      assert.match(context.prompt, /开发前必读 Architecture\.md/);
      assert.match(context.prompt, /MUST NOT 对仓库根做无界 glob/);
      assert.match(context.prompt, /\.svn/);
      assert.match(context.prompt, /features\/kanban/);
      assert.match(context.prompt, /cardKind/);
      assert.match(context.prompt, /一律为实施卡|否则为实施卡/);
      assert.equal(
        readFileSync(context.attachmentPaths[0]!, "utf8"),
        "附件内容",
      );
    } finally {
      context.cleanup();
      assert.equal(existsSync(context.tempDir), false);
      rmSync(root, { recursive: true, force: true });
    }
  });
});
