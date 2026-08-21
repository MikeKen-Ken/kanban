import { join } from "node:path";

/** Codex 的 Windows shell runner 不应继承被用户改成 pwsh 的 ComSpec。 */
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
