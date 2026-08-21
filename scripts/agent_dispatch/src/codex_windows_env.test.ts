import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { buildCodexProcessEnv } from "./codex_windows_env.ts";

describe("codex_windows_env", () => {
  it("在 Windows 上将 ComSpec 固定到系统 cmd.exe", () => {
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

  it("在非 Windows 平台只复制环境变量", () => {
    if (process.platform === "win32") return;
    const env = buildCodexProcessEnv({ PATH: "preserved" });
    assert.deepEqual(env, { PATH: "preserved" });
  });
});
