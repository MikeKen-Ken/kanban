import { workerLog } from "./worker_log.ts";

/** SDK 1.0.28 在过滤前打出的 Rule / Skill 扫描日志。 */
export type CursorSdkScanLog = {
  kind: "skills" | "rules";
  ruleCount?: number;
  skillCount?: number;
};

/**
 * SDK 本地运行会先扫描用户主目录（含内置 `skills-cursor`），再按
 * `settingSources` 的 allowedRoots 过滤。Worker 启用 `project,user`：
 * SDK 会保留用户和仓库中的 Skill，并按其 frontmatter 触发条件选择；
 * 用户 Rule 仍会由 Worker 注入完整文本。
 */
export function parseCursorSdkScanLog(line: string): CursorSdkScanLog | undefined {
  const text = line.trim();
  if (text.includes("AgentSkillsCursorRulesService load completed")) {
    return {
      kind: "skills",
      ruleCount: readMetaCount(text, "ruleCount"),
      skillCount: readMetaCount(text, "skillCount"),
    };
  }
  if (text.includes("LocalCursorRulesService load completed")) {
    return {
      kind: "rules",
      ruleCount: readMetaCount(text, "ruleCount"),
    };
  }
  return undefined;
}

export function formatCursorSdkScanNote(scan: CursorSdkScanLog): string {
  if (scan.kind === "skills") {
    const count = formatCount(scan.skillCount ?? scan.ruleCount);
    return (
      `SDK 扫描 Skill：${count}（含本机 ~/.cursor/skills-cursor 内置），` +
      "这是可供 Cursor 按触发条件选择的 Skill；不会将全部 Skill 正文同时注入"
    );
  }
  const count = formatCount(scan.ruleCount);
  return (
    `SDK 扫描 Rule：${count}，这是过滤前的扫描数；` +
    "用户 Rule 已由 Worker 写入 prompt；SDK 同时加载项目与用户设置层"
  );
}

/** 与 SDK 1.0.28 `allowedRoots` 前缀匹配一致：反斜杠当成 `/`。 */
export function isAllowedByProjectSettingSource(
  fullPath: string,
  projectRoots: readonly string[],
): boolean {
  const normalized = normalizeFsPath(fullPath);
  return projectRoots.some((root) => {
    const prefix = normalizeFsPath(root);
    return normalized === prefix || normalized.startsWith(`${prefix}/`);
  });
}

export function createCursorSdkScanLogBuffer(
  onNote: (note: string) => void,
): { push(chunk: string): void; flush(): void } {
  let pending = "";
  const emit = (line: string): void => {
    const scan = parseCursorSdkScanLog(line);
    if (scan) onNote(formatCursorSdkScanNote(scan));
  };
  return {
    push(chunk: string): void {
      pending += chunk.replaceAll("\r\n", "\n").replaceAll("\r", "\n");
      let index = pending.indexOf("\n");
      while (index >= 0) {
        emit(pending.slice(0, index));
        pending = pending.slice(index + 1);
        index = pending.indexOf("\n");
      }
    },
    flush(): void {
      if (!pending) return;
      emit(pending);
      pending = "";
    },
  };
}

/** 截获 SDK 打到 stdout/stderr 的扫描日志，补一行「扫描 ≠ 注入」。 */
export function installCursorSdkScanLogTap(
  log: (line: string) => void = (line) => workerLog(line),
): () => void {
  const buffer = createCursorSdkScanLogBuffer(log);
  const restoreStdout = wrapWriteStream(process.stdout, buffer);
  const restoreStderr = wrapWriteStream(process.stderr, buffer);
  return () => {
    buffer.flush();
    restoreStdout();
    restoreStderr();
  };
}

function readMetaCount(text: string, key: string): number | undefined {
  const match = new RegExp(`${key}\\s*[:=]\\s*(\\d+)`).exec(text);
  if (!match) return undefined;
  return Number.parseInt(match[1] ?? "", 10);
}

function formatCount(value: number | undefined): string {
  return value == null || !Number.isFinite(value) ? "若干" : `${value} 个`;
}

function normalizeFsPath(value: string): string {
  return value.replaceAll("\\", "/").replace(/\/+$/, "");
}

type WriteFn = typeof process.stdout.write;

function wrapWriteStream(
  stream: NodeJS.WriteStream,
  buffer: { push(chunk: string): void },
): () => void {
  const original = stream.write.bind(stream) as WriteFn;
  const wrapped: WriteFn = ((
    chunk: unknown,
    encoding?: BufferEncoding | ((error?: Error | null) => void),
    callback?: (error?: Error | null) => void,
  ) => {
    const encodingName = typeof encoding === "string" ? encoding : "utf8";
    const text = Buffer.isBuffer(chunk)
      ? chunk.toString(encodingName)
      : typeof chunk === "string"
        ? chunk
        : String(chunk ?? "");
    buffer.push(text);
    if (typeof encoding === "function") {
      return original(chunk as never, encoding);
    }
    return original(chunk as never, encoding, callback);
  }) as WriteFn;
  stream.write = wrapped;
  return () => {
    stream.write = original;
  };
}
