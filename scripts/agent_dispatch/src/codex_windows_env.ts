import { join } from "node:path";

/** Codex \u7684 Windows shell runner \u4E0D\u5E94\u7EE7\u627F\u88AB\u7528\u6237\u6539\u6210 pwsh \u7684 ComSpec。 */
export function buildCodexProcessEnv(
  env: NodeJS.ProcessEnv = process.env,
): NodeJS.ProcessEnv {
  if (process.platform !== "win32") return { ...env };

  const systemRoot = env.SystemRoot ?? env.SYSTEMROOT;
  const commandShell = systemRoot
    ? join(systemRoot, "System32", "cmd.exe")
    : "cmd.exe";
  return {
    ...env,
    ComSpec: commandShell,
    COMSPEC: commandShell,
  };
}
