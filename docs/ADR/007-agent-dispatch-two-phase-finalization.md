# ADR-007：Agent 调度两阶段收尾

- Status: accepted
- Date: 2026-08-16
- Updated: 2026-08-26

## 背景

Agent 直接提交 Git 并移动卡片会把“声明完成、验证、提交、更新看板”混成一个不可恢复
动作。进程在 Git commit 后、看板落盘前退出时，还会留下无法可靠判断的中间状态。

## 决策

1. Agent 只能通过 scoped `ready_to_submit` 声明完成，显式给出
   `completedChecklistIds`、`completedFeedbackIds`。卡片 `agentRequireTests` 缺省或为 true 时，验证在 Agent 会话内完成且必须通过；为 false 时不要求自动化测试，但必须传 `manualVerificationReason=本卡已配置无需测试`。不得把 `verificationCommands` 交给 Worker 代跑。该调用只持久化，不提交 Git、不勾选完成项、不移动卡片。
2. ready 中的完成项 id 必须属于 claim 时冻结的未完成范围。空列表表示本轮不完成该类
   项目，不得隐式勾选全部。
3. 本机 pending 记录按会话保存，状态为 `declared`、`validated`、`committing`、
   `committed`、`finalized`、`failed`。它不进入工作区 JSON、备份或 WebDAV。
4. Worker 通过私有 dispatch 工具记录空验证结果（会话内已验证或人工原因）并驱动
   finalize，不再 spawn 测试命令。finalize 必须把 HEAD 与 claim baseline 对齐：若
   HEAD 仍等于 baseline 则继续；若 baseline 是 HEAD 的祖先（Agent 在领取后自行
   `commit`），Worker 执行 `git reset --soft <baseline>`，把已提交内容留在暂存区，
   再走既有统一提交路径写入 session/card trailers。checkout、rebase、reset 到与
   baseline 无祖先关系的历史上时直接拒绝。受控 `gitRevertCommit` 仍要求 baseline
   未漂移，不把 Agent 超前提交折进 revert。Worker 把会话内 Shell 起止报到
   `dispatch_report_shell_span`。`ready_to_submit` 若发现验证命令尚未按其
   `executionTime` 结束（含 SDK 提前发出 completed），或最后一次有效测试
   exitCode≠0，必须拒绝。结束时间以 `startedAt + executionTime` 为准，不得用滞后
   的观察时刻覆盖。Windows PowerShell 5.1 无法执行的 `cd ... &&` 短失败从未真正
   跑测试，不得覆盖已通过的验证。Agent 应等待或重跑测试后再声明。
5. 提交前读取 Git 变更清单。发现 `.env`、凭据、私钥或同类敏感文件时直接拒绝，不能仅
   依赖 pathspec 排除后继续提交。
6. Git 提交必须带稳定的 session/card trailers。commit 后必须确认工作区 clean，再写入
   `commitRef`、只勾 ready 显式声明的 id，将验证摘要记入 Activity，并将卡片移入「待验证」。
   若提交后工作区仍脏，保留 `committed`、写入错误并拒绝看板更新，供清理后恢复；不得改成
   `failed` 以免丢失已创建提交。
7. finalize 是幂等的：`committed` 状态可继续完成看板写入；重复调用 `finalized` 返回既有
   结果。`committing` 状态应优先按 trailers 查找已创建提交并恢复。
8. 咨询卡仍可由 `submit_consultation` 直接送验，但 scoped 端点必须校验本会话 cardId。
9. block、fail、skip 和关闭临时端点由 Worker 私有工具显式执行并记录状态。
10. `ready_to_submit.gitRevertCommit` 仅接受卡片明确要求的 7–64 位提交哈希。Worker 在
    baseline 未漂移且领取后工作区干净时执行 `git revert --no-commit <hash>`，再通过既有
    统一提交路径创建带 session/card trailers 的提交；冲突会自动 abort。不得借此开放
    Agent 自行 `reset`、`rebase`、`checkout`、`push` 或移动 HEAD。Worker 仅可对
    baseline 的后代执行 `reset --soft` 以恢复领取点，不得用于其它历史改写。

## 结果

- Agent 的完成声明与可信收尾分离，Git 和看板之间的中断可恢复。
- 清单与反馈只按显式 id 更新，不会因“提交成功”而自动勾全。
- Worker 可以依据持久化状态确定继续、恢复或停止，而无需解析模型最终文字。
- 测试框架与命令随目标仓库变化，由 Agent 会话决定，调度层不按语言写死或复跑。
