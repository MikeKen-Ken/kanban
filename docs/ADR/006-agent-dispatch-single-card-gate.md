# ADR-006: Worker 原子领取的单卡 Skill 会话

- Status: accepted
- Date: 2026-08-13

## 背景

Agent 调度不能依赖 AI 最终回复中的成功标记决定是否继续。由 Agent 自行
`pick_next_card` 会在会话启动、模型覆盖和卡片绑定之间留下竞态，也无法在启动前
确定本轮唯一工具端点。领取动作应由持有私有 token 的 Worker 原子完成。

## 决策

1. 一个批次由一个 Worker 进程负责串行循环。
2. Worker 使用私有 `dispatch_claim_next_card(workerToken, expectedCardId?)` 原子领取：
   MCP 必须使用 token 所绑定的 `projectId`，完成选卡、移列、冻结提交范围、记录 Git
   baseline，并为该 token/card 创建临时 scoped MCP 端点。
3. claim 返回完整卡片上下文、附件内容、实际卡片的模型覆盖和临时 endpoint；空队列不创建
   Agent 会话。`expectedCardId` 与实际下一张不一致时拒绝领取。
4. Worker 使用 claim 结果创建全新的 Cursor SDK Agent 或 `codex exec` 会话，并注入
   已冻结的卡片上下文；Agent 不再调用 `pick_next_card`。
5. token 不进入 AI 提示。每个临时端点只绑定本轮 cardId，并只暴露 scoped Agent 工具。
6. 每轮 claim 前，Worker 在仓库目录执行 `git status --short`：工作区不干净则不领取并
   停止批次；非 Git 目录则跳过检查。
7. Cursor 以 `run.wait()` 的 `finished/error`、Codex 以独立进程退出码判断会话是否结束，不解析 AI 最终文字。
8. 会话结束后，Worker 读取 pending 状态并执行私有校验、提交与 finalize；进入待验证才
   继续，进入阻塞或失败则按确定性状态处理。
9. Worker 再次 claim；空队列或达到上限时结束批次。
10. Agent 临时端点只暴露 `ready_to_submit`、`submit_consultation`、`block_card`。
    Worker 与 IDE 使用常驻完整工具目录及私有 dispatch 工具。
11. 实施卡由 Agent 调用 `ready_to_submit` 声明完成；Git 提交与送验由 Worker 驱动的
    两阶段 finalize 完成。Agent 不得自行 `git commit` 或移动 HEAD。

## 实现约束

- scoped MCP 与完整目录共用 `/mcp` 路径，靠每会话临时端口区分。临时端口启动失败时
  不得回退完整工具目录。
- Cursor 会话只注入该精简端点。Codex 使用临时 `CODEX_HOME`（复制用户 `auth.json`、只写精简 `kanbanMCP`），避免加载用户全局 MCP。
- 调度中 `ready_to_submit` / `block_card` / `submit_consultation` 只能操作本轮领取的卡片。
- 完整 MCP 在活跃锁下不得绕过锁定卡的 submit、block、checklist 或 feedback 契约。
- claim 失败或空队列不占用本轮名额，且不得创建临时端点。
- finalize 必须拒绝 HEAD 相对 baseline 被 Agent 移动，并按 ADR-007 执行。

## 结果

- AI 不控制批次循环，也不需要输出任何调度标记。
- Worker 原子领取卡片并获得本轮唯一端点，Agent 只处理注入的卡片。
- 每张卡片对应一次新的顶层 Agent 会话，端点与 cardId 一一绑定。
- 调度期间，完整 MCP 无法绕过本轮卡片锁或提前送验。
