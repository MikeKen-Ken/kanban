import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { isRetryableError, withRetry } from "./retry.ts";

describe("retry", () => {
  it("\u8BC6\u522B SDK \u6807\u8BB0、\u7F51\u7EDC\u9519\u8BEF\u7801\u548C\u5D4C\u5957\u539F\u56E0", () => {
    assert.equal(isRetryableError({ isRetryable: true }), true);
    assert.equal(isRetryableError({ code: "ECONNRESET" }), true);
    assert.equal(
      isRetryableError(new Error("fetch failed", {
        cause: new Error("UND_ERR_CONNECT_TIMEOUT"),
      })),
      true,
    );
    assert.equal(isRetryableError({ status: 503, message: "\u4E0D\u53EF\u7528" }), true);
    assert.equal(
      isRetryableError({
        isRetryable: false,
        message: "connection closed before response completed",
      }),
      true,
    );
    assert.equal(isRetryableError("server overloaded, retry later"), true);
  });

  it("\u4E0D\u91CD\u8BD5\u9274\u6743\u548C\u914D\u7F6E\u9519\u8BEF", () => {
    assert.equal(isRetryableError({ status: 401, message: "unauthorized" }), false);
    assert.equal(isRetryableError(new Error("invalid model")), false);
  });

  it("\u6309\u6307\u6570\u9000\u907F\u91CD\u8BD5\u5E76\u8FD4\u56DE\u6210\u529F\u7ED3\u679C", async () => {
    let attempts = 0;
    const delays: number[] = [];
    const result = await withRetry(
      "\u6D4B\u8BD5\u64CD\u4F5C",
      async () => {
        attempts += 1;
        if (attempts < 3) throw new Error("network temporarily unavailable");
        return "\u5B8C\u6210";
      },
      {
        sleep: async (ms) => {
          delays.push(ms);
        },
      },
    );

    assert.equal(result, "\u5B8C\u6210");
    assert.equal(attempts, 3);
    assert.deepEqual(delays, [1000, 2000]);
  });
});
