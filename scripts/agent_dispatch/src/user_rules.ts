import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { homedir } from "node:os";
import { join, relative } from "node:path";

export type UserRuleBundle = {
  text: string;
  count: number;
  bytes: number;
};

const RULE_EXTENSIONS = new Set([".md", ".mdc"]);

/** \u5B8C\u6574\u8BFB\u53D6\u7528\u6237 ~/.cursor/rules；\u53EA\u6392\u9664\u975E\u89C4\u5219\u6587\u4EF6。 */
export function readUserCursorRules(
  root = join(homedir(), ".cursor", "rules"),
): UserRuleBundle {
  if (!existsSync(root)) return { text: "", count: 0, bytes: 0 };

  const paths = collectRulePaths(root).sort((a, b) => a.localeCompare(b));
  const sections: string[] = [];
  let bytes = 0;
  for (const path of paths) {
    const content = readFileSync(path, "utf8");
    bytes += Buffer.byteLength(content, "utf8");
    sections.push(
      [`## User rule: ${relative(root, path).replaceAll("\\", "/")}`, "", content]
        .join("\n"),
    );
  }
  return {
    text: sections.join("\n\n"),
    count: paths.length,
    bytes,
  };
}

function collectRulePaths(root: string): string[] {
  const result: string[] = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) {
      result.push(...collectRulePaths(path));
      continue;
    }
    if (!entry.isFile() || !statSync(path).isFile()) continue;
    const dot = entry.name.lastIndexOf(".");
    const extension = dot < 0 ? "" : entry.name.slice(dot).toLowerCase();
    if (RULE_EXTENSIONS.has(extension)) result.push(path);
  }
  return result;
}
