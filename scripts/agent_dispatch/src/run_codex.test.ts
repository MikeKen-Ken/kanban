import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildCodexExecArgs } from "./run_codex.ts";

describe("buildCodexExecArgs", () => {
  it("使用 sandbox workspace-write 与 approve-for-me，不再传 --full-auto", () => {
    const args = buildCodexExecArgs({
      cwd: "C:\\repo",
      lastMessageFile: "last.txt",
      extraConfigArgs: ["-c", "model_reasoning_effort=low"],
      model: "gpt-5.6-sol",
    });
    assert.equal(args.includes("--full-auto"), false);
    assert.deepEqual(args.slice(0, 5), [
      "exec",
      "--sandbox",
      "workspace-write",
      "--approve-for-me",
      "--skip-git-repo-check",
    ]);
    assert.deepEqual(args, [
      "exec",
      "--sandbox",
      "workspace-write",
      "--approve-for-me",
      "--skip-git-repo-check",
      "--cd",
      "C:\\repo",
      "-o",
      "last.txt",
      "-c",
      "model_reasoning_effort=low",
      "-m",
      "gpt-5.6-sol",
      "-",
    ]);
  });

  it("无模型时不追加 -m", () => {
    const args = buildCodexExecArgs({
      cwd: "/tmp/repo",
      lastMessageFile: "last.txt",
    });
    assert.equal(args.includes("-m"), false);
    assert.equal(args.at(-1), "-");
  });
});
