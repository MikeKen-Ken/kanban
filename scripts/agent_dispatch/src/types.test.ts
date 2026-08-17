import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  applyLiveJobOverlay,
  effortToCodexConfigArgs,
  ensureContextParameter,
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

describe("mergeJobWithCardOverrides", () => {
  it("解析 k/m 与纯数字 token 预算", () => {
    assert.equal(parseTokenBudget("272k"), 272_000);
    assert.equal(parseTokenBudget("64k"), 64_000);
    assert.equal(parseTokenBudget("272000"), 272_000);
    assert.equal(parseTokenBudget("1m"), 1_000_000);
    assert.equal(parseTokenBudget("max"), undefined);
  });

  it("未禁止时卡片参数覆盖工作台", () => {
    const merged = mergeJobWithCardOverrides(
      {
        ...job,
        modelParams: [
          { id: "reasoning_effort", value: "medium" },
          { id: "context", value: "64k" },
        ],
      },
      {
        agentModelParamValues: { context: "272k", reasoning_effort: "high" },
      },
    );
    assert.equal(
      merged.modelParams?.find((item) => item.id === "context")?.value,
      "272k",
    );
    assert.equal(
      merged.modelParams?.find((item) => item.id === "reasoning_effort")?.value,
      "high",
    );
  });

  it("卡片允许脏工作区时覆盖工作台默认", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentAllowDirtyWorkspace: true,
    });
    assert.equal(merged.allowDirtyWorkspace, true);
  });

  it("卡片开沙箱时覆盖工作台默认", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentEnableSandbox: true,
    });
    assert.equal(merged.enableSandbox, true);
  });

  it("禁止使用卡片参数时忽略卡片脏工作区开关", () => {
    const merged = mergeJobWithCardOverrides(
      { ...job, ignoreCardParams: true },
      { agentAllowDirtyWorkspace: true },
    );
    assert.equal(merged.allowDirtyWorkspace, undefined);
  });

  it("禁止使用卡片参数时忽略卡片沙箱开关", () => {
    const merged = mergeJobWithCardOverrides(
      { ...job, ignoreCardParams: true },
      { agentEnableSandbox: true },
    );
    assert.equal(merged.enableSandbox, undefined);
  });

  it("禁止使用卡片参数时只用工作台默认", () => {
    const merged = mergeJobWithCardOverrides(
      {
        ...job,
        ignoreCardParams: true,
        model: "composer-2.5",
        modelParams: [
          { id: "reasoning_effort", value: "medium" },
          { id: "context", value: "64k" },
        ],
      },
      {
        agentEngine: "codex",
        agentModelId: "gpt-5",
        agentModelParamValues: { context: "272k", reasoning_effort: "high" },
      },
    );
    assert.equal(merged.engine, "cursor");
    assert.equal(merged.model, "composer-2.5");
    assert.equal(
      merged.modelParams?.find((item) => item.id === "context")?.value,
      "64k",
    );
    assert.equal(
      merged.modelParams?.find((item) => item.id === "reasoning_effort")?.value,
      "medium",
    );
  });

  it("卡片未指定时沿用工作台默认参数", () => {
    const merged = mergeJobWithCardOverrides(
      {
        ...job,
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

  it("resolveModelParams 保留所选上下文", () => {
    const params = resolveModelParams({
      ...job,
      modelParams: [{ id: "context", value: "272k" }],
    });
    assert.equal(params?.find((item) => item.id === "context")?.value, "272k");
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

describe("applyLiveJobOverlay", () => {
  it("用运行中写入的默认平台和模型覆盖启动快照", () => {
    const live = applyLiveJobOverlay(job, {
      engine: "codex",
      model: "gpt-5",
      modelParams: [{ id: "model_reasoning_effort", value: "low" }],
    });
    assert.equal(live.engine, "codex");
    assert.equal(live.model, "gpt-5");
    assert.deepEqual(live.modelParams, [
      { id: "model_reasoning_effort", value: "low" },
    ]);
    assert.equal(live.cwd, job.cwd);
    assert.equal(live.cardLimit, job.cardLimit);
  });
});
