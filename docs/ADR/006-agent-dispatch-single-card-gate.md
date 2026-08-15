# ADR-006：Worker 驱动的单卡 Skill 会话

- Status: accepted
- Date: 2026-08-13

## 背景

Agent 调度不能依赖 AI 最终回复中的成功标记决定是否继续，也不应由 Worker 代替 Skill 领取卡片。期望语义是：每次全新会话只发送 Skill（可附项目名），Skill 自己领取并处理一张卡；Worker 仅负责检查队列和拉起下一次会话。

## 决策

1. 一个批次由一个 Worker 进程负责串行循环。
2. Worker 使用只读 `peek_next_card` 判断是否还有待办或待返工，不领取、不移动卡片。
3. 有卡时，Worker 创建全新的 Cursor SDK Agent 或 `codex exec` 会话，只发送 Skill 全文和可选项目名。
4. Skill 在会话内自行调用 `pick_next_card` 并完成单卡流程。
5. 每轮开始前，Worker 通过私有 token 重置 MCP 单卡闸门；本轮第二次 `pick_next_card` 由 MCP 拒绝。token 不进入 AI 提示。
6. 每轮创建 Skill 会话前，Worker 在仓库目录执行 `git status --short`：工作区不干净则不创建会话并停止批次；非 Git 目录则跳过检查。
7. Cursor 以 `run.wait()` 的 `finished/error`、Codex 以独立进程退出码判断会话是否结束，不解析 AI 最终文字。
8. 会话结束后，Worker 根据闸门记录的 cardId 读取看板状态：进入待验证才继续；进入阻塞或仍在其他列则停止。
9. Worker 再次只读检查队列；无卡或达到上限时结束批次。
10. Skill 会话连接独立 MCP 端点，只暴露 `pick_next_card`、`submit_consultation`、`commit_and_submit_card`、`block_card`。Worker 与 IDE 仍使用完整工具目录。
11. 实施卡收尾由 `commit_and_submit_card` 在看板进程内提交（如有 Git）并移入待验证；AI 不得自行 `git commit`。

## 结果

- AI 不控制批次循环，也不需要输出任何调度标记。
- Worker 不领取卡片，只负责队列检查、会话生命周期和确定性状态判断。
- 每张卡片对应一次新的顶层 Agent 会话，同一会话无法领取第二张卡。
- 调度期间，并发的普通 `pick_next_card` 会受当前单卡闸门影响。
