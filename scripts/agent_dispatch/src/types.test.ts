import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  clampUnattendedParam,
  mergeJobWithCardOverrides,
  parseTokenBudget,
  resolveModelParams,
  type DispatchJob,
} from "./types.ts";

const job: DispatchJob = {
  engine: "cursor",
  cwd: process.cwd(),
  prompt: "基础指令",
  mcpEndpoint: "http://full/mcp",
  cardLimit: 1,
  workerToken: "worker-secret",
  outPath: "unused.json",
};

describe("clampUnattendedParam", () => {
  it("解析 k/m 与纯数字 token 预算", () => {
    assert.equal(parseTokenBudget("272k"), 272_000);
    assert.equal(parseTokenBudget("64k"), 64_000);
    assert.equal(parseTokenBudget("272000"), 272_000);
    assert.equal(parseTokenBudget("1m"), 1_000_000);
    assert.equal(parseTokenBudget("max"), undefined);
  });

  it("把超过 64k 的上下文收到 64k", () => {
    assert.equal(
      clampUnattendedParam({ id: "context", value: "272k" }, false),
      "64k",
    );
    assert.equal(
      clampUnattendedParam({ id: "contextWindow", value: "272000" }, false),
      "64k",
    );
    assert.equal(
      clampUnattendedParam({ id: "context", value: "100k" }, false),
      "64k",
    );
    assert.equal(
      clampUnattendedParam({ id: "context", value: "64k" }, false),
      "64k",
    );
    assert.equal(
      clampUnattendedParam({ id: "context", value: "32k" }, false),
      "32k",
    );
  });

  it("允许高推理时仍钳制超大上下文", () => {
    assert.equal(
      clampUnattendedParam({ id: "context", value: "272k" }, true),
      "64k",
    );
    assert.equal(
      clampUnattendedParam({ id: "reasoning_effort", value: "high" }, true),
      "high",
    );
  });

  it("无人值守时把 high 推理收到 medium", () => {
    assert.equal(
      clampUnattendedParam({ id: "reasoning_effort", value: "high" }, false),
      "medium",
    );
  });

  it("merge 卡片覆盖时钳制超大上下文", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentModelParamValues: { context: "272k" },
    });
    assert.equal(
      merged.modelParams?.find((item) => item.id === "context")?.value,
      "64k",
    );
  });

  it("resolveModelParams 同样钳制超大上下文", () => {
    const params = resolveModelParams({
      ...job,
      modelParams: [{ id: "context", value: "272k" }],
    });
    assert.equal(params?.find((item) => item.id === "context")?.value, "64k");
  });
});
