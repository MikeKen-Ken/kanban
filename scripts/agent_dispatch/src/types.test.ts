import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  clampUnattendedParam,
  effortToCodexConfigArgs,
  ensureContextParameter,
  mergeJobWithCardOverrides,
  parseTokenBudget,
  resolveAllowHighReasoning,
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

  it("关闭高费用时把超过 64k 的上下文收到 64k", () => {
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

  it("打开高费用时保留卡片/面板的推理、Fast 与上下文", () => {
    assert.equal(
      clampUnattendedParam({ id: "context", value: "272k" }, true),
      "272k",
    );
    assert.equal(
      clampUnattendedParam({ id: "reasoning_effort", value: "high" }, true),
      "high",
    );
    assert.equal(
      clampUnattendedParam({ id: "fast", value: "true" }, true),
      "true",
    );
  });

  it("无人值守时把 high 推理收到 medium", () => {
    assert.equal(
      clampUnattendedParam({ id: "reasoning_effort", value: "high" }, false),
      "medium",
    );
  });

  it("merge 卡片覆盖时在关闭高费用下钳制超大上下文", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentModelParamValues: { context: "272k" },
    });
    assert.equal(
      merged.modelParams?.find((item) => item.id === "context")?.value,
      "64k",
    );
  });

  it("卡片打开高费用时覆盖工作台并保留 272k", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentAllowHighReasoning: true,
      agentModelParamValues: { context: "272k", reasoning_effort: "high" },
    });
    assert.equal(merged.allowHighReasoning, true);
    assert.equal(
      merged.modelParams?.find((item) => item.id === "context")?.value,
      "272k",
    );
    assert.equal(
      merged.modelParams?.find((item) => item.id === "reasoning_effort")?.value,
      "high",
    );
  });

  it("卡片关闭高费用时即使工作台打开也钳制", () => {
    const merged = mergeJobWithCardOverrides(
      { ...job, allowHighReasoning: true },
      {
        agentAllowHighReasoning: false,
        agentModelParamValues: { context: "272k" },
      },
    );
    assert.equal(merged.allowHighReasoning, false);
    assert.equal(
      merged.modelParams?.find((item) => item.id === "context")?.value,
      "64k",
    );
  });

  it("卡片未指定时沿用工作台默认参数", () => {
    const merged = mergeJobWithCardOverrides(
      {
        ...job,
        allowHighReasoning: true,
        modelParams: [
          { id: "reasoning_effort", value: "medium" },
          { id: "context", value: "64k" },
        ],
      },
      {},
    );
    assert.equal(
      merged.modelParams?.find((item) => item.id === "reasoning_effort")?.value,
      "medium",
    );
    assert.equal(
      merged.modelParams?.find((item) => item.id === "context")?.value,
      "64k",
    );
  });

  it("resolveModelParams 在关闭高费用时钳制超大上下文", () => {
    const params = resolveModelParams({
      ...job,
      modelParams: [{ id: "context", value: "272k" }],
    });
    assert.equal(params?.find((item) => item.id === "context")?.value, "64k");
  });

  it("卡片未写覆盖时沿用工作台开关", () => {
    assert.equal(resolveAllowHighReasoning(job, {}), false);
    assert.equal(
      resolveAllowHighReasoning({ ...job, allowHighReasoning: true }, {}),
      true,
    );
  });

  it("缺上下文参数时补上 64k/272k", () => {
    const parameters = ensureContextParameter([
      { id: "reasoning_effort", values: ["low", "medium", "high"] },
    ]);
    assert.equal(parameters.at(-1)?.id, "context");
    assert.deepEqual(parameters.at(-1)?.values, ["64k", "272k"]);
  });

  it("Codex 把上下文写成 model_context_window", () => {
    assert.deepEqual(
      effortToCodexConfigArgs({
        ...job,
        allowHighReasoning: true,
        modelParams: [
          { id: "model_reasoning_effort", value: "high" },
          { id: "context", value: "272k" },
        ],
      }),
      [
        "-c",
        "model_reasoning_effort=high",
        "-c",
        "model_context_window=272000",
      ],
    );
  });
});
