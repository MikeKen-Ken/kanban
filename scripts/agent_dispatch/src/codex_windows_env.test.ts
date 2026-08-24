import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildCodexProcessEnv } from "./codex_windows_env.ts";

describe("codex_windows_env", () => {
  it("\u5728 Windows \u4E0A\u5C06 ComSpec \u56FA\u5B9A\u5230\u7CFB\u7EDF cmd.exe", () => {
    if (process.platform !== "win32") return;
    const env = buildCodexProcessEnv({
      ComSpec: String.raw`C:\Users\me\AppData\Local\Microsoft\WindowsApps\pwsh.exe`,
      COMSPEC: String.raw`C:\Users\me\AppData\Local\Microsoft\WindowsApps\pwsh.exe`,
      SystemRoot: String.raw`C:\Windows`,
      CODEX_HOME: "preserved",
    });
    assert.equal(env.ComSpec, String.raw`C:\Windows\System32\cmd.exe`);
    assert.equal(env.COMSPEC, String.raw`C:\Windows\System32\cmd.exe`);
    assert.equal(env.CODEX_HOME, "preserved");
  });

  it("\u5728\u975E Windows \u5E73\u53F0\u53EA\u590D\u5236\u73AF\u5883\u53D8\u91CF", () => {
    if (process.platform === "win32") return;
    const env = buildCodexProcessEnv({ PATH: "preserved" });
    assert.deepEqual(env, { PATH: "preserved" });
  });
});
