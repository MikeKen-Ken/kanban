import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildCodexExecArgs } from "./run_codex.ts";

describe("buildCodexExecArgs", () => {
  it("\u5F00\u542F\u6C99\u7BB1\u65F6\u4F7F\u7528 --approve-for-me \u4F5C\u4E3A\u65E0\u4EBA\u503C\u5B88\u7B49\u4EF7，\u4E0D\u518D\u53E0\u52A0 --sandbox", () => {
    const args = buildCodexExecArgs({
      cwd: "C:\\repo",
      lastMessageFile: "last.txt",
      extraConfigArgs: ["-c", "model_reasoning_effort=low"],
      model: "gpt-5.6-sol",
      enableSandbox: true,
    });
    assert.equal(args.includes("--full-auto"), false);
    assert.equal(args.includes("--sandbox"), false);
    assert.deepEqual(args.slice(0, 4), [
      "exec",
      "--json",
      "--approve-for-me",
      "--skip-git-repo-check",
    ]);
    const expected = [
      "exec",
      "--json",
      "--approve-for-me",
      "--skip-git-repo-check",
      "--cd",
      "C:\\repo",
      "-o",
      "last.txt",
      "-c",
      "model_reasoning_effort=low",
      ...(process.platform === "win32"
        ? ["-c", 'windows.sandbox="unelevated"']
        : []),
      "-m",
      "gpt-5.6-sol",
      "-",
    ];
    assert.deepEqual(args, expected);
  });

  it("\u5173\u95ED\u6C99\u7BB1\u65F6\u7ED5\u8FC7 Codex \u7684\u81EA\u52A8\u5BA1\u6279\u6C99\u7BB1", () => {
    const args = buildCodexExecArgs({
      cwd: "C:\\repo",
      lastMessageFile: "last.txt",
      enableSandbox: false,
    });

    assert.equal(args.includes("--approve-for-me"), false);
    assert.equal(args.includes("--dangerously-bypass-approvals-and-sandbox"), true);
  });

  it("\u65E0\u6A21\u578B\u65F6\u4E0D\u8FFD\u52A0 -m", () => {
    const args = buildCodexExecArgs({
      cwd: "/tmp/repo",
      lastMessageFile: "last.txt",
    });
    assert.equal(args.includes("-m"), false);
    assert.equal(args.at(-1), "-");
  });
});
