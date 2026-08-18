export type RetryOptions = {
  maxAttempts?: number;
  baseDelayMs?: number;
  sleep?: (ms: number) => Promise<void>;
  onRetry?: (event: {
    operation: string;
    attempt: number;
    maxAttempts: number;
    delayMs: number;
    error: unknown;
  }) => void;
};

const RETRYABLE_STATUS_CODES = new Set([408, 425, 429, 500, 502, 503, 504]);
const RETRYABLE_ERROR_CODES = new Set([
  "deadline_exceeded",
  "econnaborted",
  "econnrefused",
  "econnreset",
  "enetdown",
  "enetreset",
  "enetunreach",
  "etimedout",
  "resource_exhausted",
  "socket_closed",
  "und_err_connect_timeout",
  "unavailable",
]);
const RETRYABLE_MESSAGE_PARTS = [
  "connect timeout",
  "connection reset",
  "fetch failed",
  "network",
  "service unavailable",
  "socket hang up",
  "timed out",
  "timeout",
];

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function isRetryableError(error: unknown): boolean {
  if (error == null) return false;
  if (typeof error === "string") return retryableText(error);
  if (typeof error !== "object") return false;

  const record = error as Record<string, unknown>;
  if (record.isRetryable === true) return true;

  const status = Number(record.status ?? record.statusCode);
  if (Number.isFinite(status) && RETRYABLE_STATUS_CODES.has(status)) return true;

  const code = String(record.code ?? "").trim().toLowerCase();
  if (RETRYABLE_ERROR_CODES.has(code)) return true;

  const message = error instanceof Error ? error.message : String(record.message ?? "");
  if (retryableText(message)) return true;

  return "cause" in record && record.cause != null
    ? isRetryableError(record.cause)
    : false;
}

export async function withRetry<T>(
  operation: string,
  fn: () => Promise<T>,
  options: RetryOptions = {},
): Promise<T> {
  const maxAttempts = Math.max(1, Math.trunc(options.maxAttempts ?? 3));
  const baseDelayMs = Math.max(0, Math.trunc(options.baseDelayMs ?? 1000));
  const wait = options.sleep ?? sleep;
  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt >= maxAttempts || !isRetryableError(error)) throw error;

      const delayMs = baseDelayMs * 2 ** (attempt - 1);
      options.onRetry?.({
        operation,
        attempt,
        maxAttempts,
        delayMs,
        error,
      });
      await wait(delayMs);
    }
  }

  throw lastError;
}

function retryableText(value: string): boolean {
  const lower = value.toLowerCase();
  return RETRYABLE_MESSAGE_PARTS.some((part) => lower.includes(part)) ||
    [...RETRYABLE_ERROR_CODES].some((code) => lower.includes(code));
}
