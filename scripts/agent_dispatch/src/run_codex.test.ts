import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildCodexExecArgs } from "./run_codex.ts";

describe("buildCodexExecArgs", () => {
  it("使用 --approve-for-me 作为无人值守等价，不再叠加 --sandbox", () => {
    const args = buildCodexExecArgs({
      cwd: "C:\\repo",
      lastMessageFile: "last.txt",
      extraConfigArgs: ["-c", "model_reasoning_effort=low"],
      model: "gpt-5.6-sol",
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

  it("无模型时不追加 -m", () => {
    const args = buildCodexExecArgs({
      cwd: "/tmp/repo",
      lastMessageFile: "last.txt",
    });
    assert.equal(args.includes("-m"), false);
    assert.equal(args.at(-1), "-");
  });
});
