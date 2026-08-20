import { stdin } from "node:process";
import {
  cwdFromHookInput,
  evaluateGlobToolCall,
  globArgsFromUnknown,
  isGlobToolName,
  toolNameFromHookInput,
} from "./worker_glob_policy.ts";

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of stdin) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

function writeDecision(decision: { permission: "allow" | "deny"; agent_message?: string }): void {
  process.stdout.write(`${JSON.stringify(decision)}\n`);
}

const raw = await readStdin();
let parsed: unknown = {};
try {
  parsed = raw.trim() ? JSON.parse(raw) : {};
} catch {
  writeDecision({ permission: "allow" });
  process.exit(0);
}

const toolName = toolNameFromHookInput(parsed);
if (toolName && !isGlobToolName(toolName)) {
  writeDecision({ permission: "allow" });
  process.exit(0);
}

const args = globArgsFromUnknown(parsed);
if (!args.pattern && !isGlobToolName(toolName)) {
  writeDecision({ permission: "allow" });
  process.exit(0);
}

const result = evaluateGlobToolCall({
  pattern: args.pattern,
  targetDirectory: args.targetDirectory,
  cwd: cwdFromHookInput(parsed),
});
if (result.allow) {
  writeDecision({ permission: "allow" });
  process.exit(0);
}

writeDecision({
  permission: "deny",
  agent_message: result.reason,
});
process.exit(0);
