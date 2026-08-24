import { workerLog } from "./worker_log.ts";

/** SDK 1.0.28 \u5728\u8FC7\u6EE4\u524D\u6253\u51FA\u7684 Rule / Skill \u626B\u63CF\u65E5\u5FD7。 */
export type CursorSdkScanLog = {
  kind: "skills" | "rules";
  ruleCount?: number;
  skillCount?: number;
};

/**
 * SDK \u672C\u5730\u8FD0\u884C\u4F1A\u5148\u626B\u63CF\u7528\u6237\u4E3B\u76EE\u5F55（\u542B\u5185\u7F6E `skills-cursor`），\u518D\u6309
 * `settingSources` \u7684 allowedRoots \u8FC7\u6EE4。Worker \u542F\u7528 `project,user`：
 * SDK \u4F1A\u4FDD\u7559\u7528\u6237\u548C\u4ED3\u5E93\u4E2D\u7684 Skill，\u5E76\u6309\u5176 frontmatter \u89E6\u53D1\u6761\u4EF6\u9009\u62E9；
 * \u7528\u6237 Rule \u4ECD\u4F1A\u7531 Worker \u6CE8\u5165\u5B8C\u6574\u6587\u672C。
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
      `SDK scanned Skills: ${count} (including local ~/.cursor/skills-cursor builtins). ` +
      "These are Skills Cursor may select by trigger; it does not inject every Skill body at once."
    );
  }
  const count = formatCount(scan.ruleCount);
  return (
    `SDK scanned Rules: ${count} (count before filtering). ` +
    "User Rules are already written into the prompt by the Worker; the SDK also loads project and user setting layers."
  );
}

/** \u4E0E SDK 1.0.28 `allowedRoots` \u524D\u7F00\u5339\u914D\u4E00\u81F4：\u53CD\u659C\u6760\u5F53\u6210 `/`。 */
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

/** \u622A\u83B7 SDK \u6253\u5230 stdout/stderr \u7684\u626B\u63CF\u65E5\u5FD7，\u8865\u4E00\u884C「\u626B\u63CF ≠ \u6CE8\u5165」。 */
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
  return value == null || !Number.isFinite(value) ? "several" : `${value}`;
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
