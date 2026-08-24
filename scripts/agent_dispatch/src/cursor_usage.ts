import { Cursor } from "@cursor/sdk";

type UsagePayload = {
  ok: boolean;
  userEmail?: string;
  apiKeyName?: string;
  autoRemainingPercent?: number;
  apiRemainingPercent?: number;
  message?: string;
  error?: string;
};

function readPercent(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.min(100, value));
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed)
      ? Math.max(0, Math.min(100, parsed))
      : undefined;
  }
  return undefined;
}

function pickPercent(
  record: Record<string, unknown>,
  keys: string[],
): number | undefined {
  for (const key of keys) {
    const value = readPercent(record[key]);
    if (value != null) return value;
  }
  return undefined;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : null;
}

function parseUsageRecord(record: Record<string, unknown>): {
  autoRemainingPercent?: number;
  apiRemainingPercent?: number;
} {
  const nested =
    asRecord(record.usage) ??
    asRecord(record.planUsage) ??
    asRecord(record.membershipType) ??
    record;
  return {
    autoRemainingPercent: pickPercent(nested, [
      "autoRemainingPercent",
      "autoPercentRemaining",
      "autoRemaining",
      "composerRemainingPercent",
    ]),
    apiRemainingPercent: pickPercent(nested, [
      "apiRemainingPercent",
      "apiPercentRemaining",
      "apiRemaining",
    ]),
  };
}

async function tryFetchUsagePools(
  apiKey: string,
): Promise<{
  autoRemainingPercent?: number;
  apiRemainingPercent?: number;
}> {
  const endpoints = [
    "https://api.cursor.com/auth/usage",
    "https://api.cursor.com/dashboard/get-monthly-invoice",
  ];
  for (const url of endpoints) {
    try {
      const response = await fetch(url, {
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
      });
      if (!response.ok) continue;
      const json: unknown = await response.json();
      const record = asRecord(json);
      if (record == null) continue;
      const parsed = parseUsageRecord(record);
      if (
        parsed.autoRemainingPercent != null ||
        parsed.apiRemainingPercent != null
      ) {
        return parsed;
      }
    } catch {
      // \u4E2A\u4EBA\u5957\u9910\u901A\u5E38\u6CA1\u6709\u516C\u5F00\u7528\u91CF\u63A5\u53E3，\u7EE7\u7EED\u5C1D\u8BD5\u4E0B\u4E00\u4E2A。
    }
  }
  return {};
}

export async function printCursorUsage(): Promise<void> {
  const apiKey = process.env.CURSOR_API_KEY?.trim();
  if (!apiKey) {
    console.error("Missing CURSOR_API_KEY");
    process.exitCode = 2;
    return;
  }

  let me: { userEmail?: string; apiKeyName?: string } | undefined;
  try {
    me = await Cursor.me({ apiKey });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const payload: UsagePayload = {
      ok: false,
      error: `Failed to read the Cursor account: ${message}`,
    };
    process.stdout.write(`${JSON.stringify(payload)}\n`);
    process.exitCode = 2;
    return;
  }

  const pools = await tryFetchUsagePools(apiKey);
  const payload: UsagePayload = {
    ok: true,
    userEmail: me.userEmail,
    apiKeyName: me.apiKeyName,
    ...pools,
  };
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}
