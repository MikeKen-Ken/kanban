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
  prompt: "\u57FA\u7840\u6307\u4EE4",
  mcpEndpoint: "http://full/mcp",
  cardLimit: 1,
  workerToken: "worker-secret",
  outPath: "unused.json",
};

describe("mergeJobWithCardOverrides", () => {
  it("\u89E3\u6790 k/m \u4E0E\u7EAF\u6570\u5B57 token \u9884\u7B97", () => {
    assert.equal(parseTokenBudget("272k"), 272_000);
    assert.equal(parseTokenBudget("64k"), 64_000);
    assert.equal(parseTokenBudget("272000"), 272_000);
    assert.equal(parseTokenBudget("1m"), 1_000_000);
    assert.equal(parseTokenBudget("max"), undefined);
  });

  it("\u672A\u7981\u6B62\u65F6\u5361\u7247\u53C2\u6570\u8986\u76D6\u5DE5\u4F5C\u53F0", () => {
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

  it("\u5361\u7247\u5141\u8BB8\u810F\u5DE5\u4F5C\u533A\u65F6\u8986\u76D6\u5DE5\u4F5C\u53F0\u9ED8\u8BA4", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentAllowDirtyWorkspace: true,
    });
    assert.equal(merged.allowDirtyWorkspace, true);
  });

  it("\u5361\u7247\u5F00\u6C99\u7BB1\u65F6\u8986\u76D6\u5DE5\u4F5C\u53F0\u9ED8\u8BA4", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentEnableSandbox: true,
    });
    assert.equal(merged.enableSandbox, true);
  });

  it("\u7981\u6B62\u4F7F\u7528\u5361\u7247\u53C2\u6570\u65F6\u5FFD\u7565\u5361\u7247\u810F\u5DE5\u4F5C\u533A\u5F00\u5173", () => {
    const merged = mergeJobWithCardOverrides(
      { ...job, ignoreCardParams: true },
      { agentAllowDirtyWorkspace: true },
    );
    assert.equal(merged.allowDirtyWorkspace, undefined);
  });

  it("\u7981\u6B62\u4F7F\u7528\u5361\u7247\u53C2\u6570\u65F6\u5FFD\u7565\u5361\u7247\u6C99\u7BB1\u5F00\u5173", () => {
    const merged = mergeJobWithCardOverrides(
      { ...job, ignoreCardParams: true },
      { agentEnableSandbox: true },
    );
    assert.equal(merged.enableSandbox, undefined);
  });

  it("\u7981\u6B62\u4F7F\u7528\u5361\u7247\u53C2\u6570\u65F6\u53EA\u7528\u5DE5\u4F5C\u53F0\u9ED8\u8BA4", () => {
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

  it("\u5361\u7247\u672A\u6307\u5B9A\u65F6\u6CBF\u7528\u5DE5\u4F5C\u53F0\u9ED8\u8BA4\u53C2\u6570", () => {
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

  it("Cursor catalog \u53EA\u6709 fast \u65F6\u4E22\u6389\u81EA\u9020 context \u548C\u601D\u8003\u53C2\u6570", () => {
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

  it("omitted context stays omitted instead of filling 64k", () => {
    const merged = mergeJobWithCardOverrides(
      {
        ...job,
        engine: "codex",
        model: "gpt-5.5",
        modelParams: [{ id: "model_reasoning_effort", value: "medium" }],
        engineDefaults: {
          codex: {
            model: "gpt-5.5",
            modelParams: [{ id: "model_reasoning_effort", value: "medium" }],
            models: [
              {
                id: "gpt-5.5",
                parameters: [
                  {
                    id: "model_reasoning_effort",
                    values: ["low", "medium", "high"],
                  },
                  { id: "context", values: ["64k", "272k"] },
                ],
              },
            ],
          },
        },
      },
      {},
    );
    assert.equal(
      merged.modelParams?.find((item) => item.id === "context"),
      undefined,
    );
    assert.equal(
      merged.modelParams?.find((item) => item.id === "model_reasoning_effort")
        ?.value,
      "medium",
    );
  });

  it("Cursor \u65E0 catalog \u65F6\u4E0D\u8981\u51ED\u7A7A\u8865 reasoning_effort", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentModelId: "composer-2.5",
      agentModelParamValues: { fast: "true" },
    });
    assert.deepEqual(merged.modelParams, [{ id: "fast", value: "true" }]);
  });

  it("selectCursorSdkModelParams \u4E22\u6389 context，\u5E76\u6309\u76EE\u5F55\u8FC7\u6EE4 fast", () => {
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

  it("\u65E0\u76EE\u5F55\u65F6 Grok \u4E0D\u8981\u628A fast \u4F20\u7ED9 SDK，Composer \u4ECD\u53EF\u4F20", () => {
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

  it("withCursorSdkCatalog \u540E\u6309\u5B9E\u65F6\u76EE\u5F55\u4E22\u6389 Grok \u7684 fast", () => {
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

  it("Agent.create \u62A5 fast \u4E0D\u652F\u6301\u65F6\u4E22\u6389\u8BE5\u53C2\u6570\u518D\u8BD5", () => {
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

  it("\u5F53\u524D\u6A21\u578B\u76EE\u5F55\u6CA1\u6709 fast \u65F6\u4E0D\u8981\u4F20\u7ED9 SDK", () => {
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

  it("resolveModelParams \u4FDD\u7559\u6240\u9009\u4E0A\u4E0B\u6587", () => {
    const params = resolveModelParams({
      ...job,
      modelParams: [{ id: "context", value: "272k" }],
    });
    assert.equal(params?.find((item) => item.id === "context")?.value, "272k");
  });

  it("\u7F3A\u4E0A\u4E0B\u6587\u53C2\u6570\u65F6\u8865\u4E0A 64k/272k", () => {
    const parameters = ensureContextParameter([
      { id: "reasoning_effort", values: ["low", "medium", "high"] },
    ]);
    assert.equal(parameters.at(-1)?.id, "context");
    assert.deepEqual(parameters.at(-1)?.values, ["64k", "272k"]);
  });

  it("Codex \u628A\u4E0A\u4E0B\u6587\u5199\u6210 model_context_window", () => {
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
  it("\u7528\u8FD0\u884C\u4E2D\u5199\u5165\u7684\u9ED8\u8BA4\u5E73\u53F0\u548C\u6A21\u578B\u8986\u76D6\u542F\u52A8\u5FEB\u7167", () => {
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

  it("\u5361\u7247\u5173\u95ED\u6D4B\u8BD5\u65F6\u8986\u76D6\u9ED8\u8BA4\u9700\u8981\u6D4B\u8BD5", () => {
    const merged = mergeJobWithCardOverrides(job, {
      agentRequireTests: false,
    });
    assert.equal(merged.requireTests, false);
  });

  it("\u5361\u7247\u5F00\u542F\u6D4B\u8BD5\u65F6\u8986\u76D6\u5DE5\u4F5C\u53F0\u9ED8\u8BA4", () => {
    const merged = mergeJobWithCardOverrides(
      { ...job, requireTests: false },
      { agentRequireTests: true },
    );
    assert.equal(merged.requireTests, true);
  });

  it("\u7981\u6B62\u5361\u7247\u53C2\u6570\u65F6\u4ECD\u8981\u6C42\u6D4B\u8BD5", () => {
    const merged = mergeJobWithCardOverrides(
      { ...job, ignoreCardParams: true },
      { agentRequireTests: false },
    );
    assert.notEqual(merged.requireTests, false);
  });

  it("\u4FDD\u7559\u8FD0\u884C\u4E2D\u5173\u95ED\u6536\u5C3E\u4E3B\u52A8\u7ED3\u675F\u4F1A\u8BDD\u7684\u8BBE\u7F6E", () => {
    const live = applyLiveJobOverlay(job, {
      terminateAfterDispatchTerminal: false,
    });
    assert.equal(live.terminateAfterDispatchTerminal, false);
  });
});
