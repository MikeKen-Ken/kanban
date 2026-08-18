import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { isRetryableError, withRetry } from "./retry.ts";

describe("retry", () => {
  it("识别 SDK 标记、网络错误码和嵌套原因", () => {
    assert.equal(isRetryableError({ isRetryable: true }), true);
    assert.equal(isRetryableError({ code: "ECONNRESET" }), true);
    assert.equal(
      isRetryableError(new Error("fetch failed", {
        cause: new Error("UND_ERR_CONNECT_TIMEOUT"),
      })),
      true,
    );
    assert.equal(isRetryableError({ status: 503, message: "不可用" }), true);
    assert.equal(
      isRetryableError({
        isRetryable: false,
        message: "connection closed before response completed",
      }),
      true,
    );
    assert.equal(isRetryableError("server overloaded, retry later"), true);
  });

  it("不重试鉴权和配置错误", () => {
    assert.equal(isRetryableError({ status: 401, message: "unauthorized" }), false);
    assert.equal(isRetryableError(new Error("invalid model")), false);
  });

  it("按指数退避重试并返回成功结果", async () => {
    let attempts = 0;
    const delays: number[] = [];
    const result = await withRetry(
      "测试操作",
      async () => {
        attempts += 1;
        if (attempts < 3) throw new Error("network temporarily unavailable");
        return "完成";
      },
      {
        sleep: async (ms) => {
          delays.push(ms);
        },
      },
    );

    assert.equal(result, "完成");
    assert.equal(attempts, 3);
    assert.deepEqual(delays, [1000, 2000]);
  });
});
