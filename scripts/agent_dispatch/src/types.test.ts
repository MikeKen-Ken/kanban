import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  applyLiveJobOverlay,
  effortToCodexConfigArgs,
  ensureContextParameter,
  mergeJobWithCardOverrides,
  parseTokenBudget,
  resolveModelParams,
  nextCursorSdkParamsAfterCreateError,
  selectCursorSdkModelParams,
  withCursorSdkCatalog,
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

  it("Cursor catalog 只有 fast 时丢掉自造 context 和思考参数", () => {
    const merged = mergeJobWithCardOverrides(
      {
        ...job,
        model: "composer-2.5",
        modelParams: [
          { id: "fast", value: "true" },
          { id: "reasoning_effort", value: "medium" },
          { id: "context", value: "64k" },
        ],
        engineDefaults: {
          cursor: {
            model: "composer-2.5",
            modelParams: [
              { id: "fast", value: "true" },
              { id: "reasoning_effort", value: "medium" },
              { id: "context", value: "64k" },
            ],
            models: [
              {
                id: "composer-2.5",
                parameters: [{ id: "fast", values: ["true", "false"] }],
              },
            ],
          },
        },
      },
      {},
    );
    assert.deepEqual(merged.modelParams, [{ id: "fast", value: "true" }]);
  });

  it("Cursor 无 catalog 时不要凭空补 reasoning_effort", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentModelId: "composer-2.5",
      agentModelParamValues: { fast: "true" },
    });
    assert.deepEqual(merged.modelParams, [{ id: "fast", value: "true" }]);
  });

  it("selectCursorSdkModelParams 丢掉 context，并按目录过滤 fast", () => {
    const selected = selectCursorSdkModelParams({
      ...job,
      model: "composer-2.5",
      modelParams: [
        { id: "fast", value: "true" },
        { id: "reasoning_effort", value: "high" },
        { id: "context", value: "272k" },
      ],
      engineDefaults: {
        cursor: {
          models: [
            {
              id: "composer-2.5",
              parameters: [{ id: "fast", values: ["true", "false"] }],
            },
          ],
        },
      },
    });
    assert.deepEqual(selected.params, [{ id: "fast", value: "true" }]);
    assert.deepEqual(selected.dropped.sort(), ["context", "reasoning_effort"]);
  });

  it("无目录时 Grok 不要把 fast 传给 SDK，Composer 仍可传", () => {
    const grok = selectCursorSdkModelParams({
      ...job,
      model: "grok-4.6",
      modelParams: [
        { id: "fast", value: "true" },
        { id: "reasoning_effort", value: "medium" },
        { id: "context", value: "64k" },
      ],
    });
    assert.deepEqual(grok.params, [{ id: "reasoning_effort", value: "medium" }]);
    assert.ok(grok.dropped.includes("fast"));

    const composer = selectCursorSdkModelParams({
      ...job,
      model: "composer-2.5",
      modelParams: [
        { id: "fast", value: "true" },
        { id: "reasoning_effort", value: "medium" },
        { id: "context", value: "64k" },
      ],
    });
    assert.deepEqual(composer.params, [{ id: "fast", value: "true" }]);
  });

  it("withCursorSdkCatalog 后按实时目录丢掉 Grok 的 fast", () => {
    const selected = selectCursorSdkModelParams(
      withCursorSdkCatalog(
        {
          ...job,
          model: "grok-4.6",
          modelParams: [{ id: "fast", value: "true" }],
        },
        [
          {
            id: "grok-4.6",
            parameters: [
              { id: "reasoning_effort", values: ["low", "medium", "high"] },
            ],
          },
        ],
      ),
    );
    assert.equal(selected.params, undefined);
    assert.ok(selected.dropped.includes("fast"));
  });

  it("Agent.create 报 fast 不支持时丢掉该参数再试", () => {
    const next = nextCursorSdkParamsAfterCreateError(
      [
        { id: "fast", value: "true" },
        { id: "reasoning_effort", value: "medium" },
      ],
      new Error("Parameter `fast` is not supported for this model"),
    );
    assert.equal(next.changed, true);
    assert.deepEqual(next.params, [{ id: "reasoning_effort", value: "medium" }]);
    assert.deepEqual(next.dropped, ["fast"]);
  });

  it("当前模型目录没有 fast 时不要传给 SDK", () => {
    const selected = selectCursorSdkModelParams({
      ...job,
      model: "grok-4.6",
      modelParams: [
        { id: "fast", value: "true" },
        { id: "reasoning_effort", value: "medium" },
        { id: "context", value: "64k" },
      ],
      engineDefaults: {
        cursor: {
          models: [
            {
              id: "grok-4.6",
              parameters: [
                { id: "reasoning_effort", values: ["low", "medium", "high"] },
              ],
            },
          ],
        },
      },
    });
    assert.deepEqual(selected.params, [
      { id: "reasoning_effort", value: "medium" },
    ]);
    assert.ok(selected.dropped.includes("fast"));
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

  it("保留运行中关闭收尾主动结束会话的设置", () => {
    const live = applyLiveJobOverlay(job, {
      terminateAfterDispatchTerminal: false,
    });
    assert.equal(live.terminateAfterDispatchTerminal, false);
  });
});
