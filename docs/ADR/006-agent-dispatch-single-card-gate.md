# ADR-006: Worker 原子领取的单卡 Skill 会话

- Status: accepted
- Date: 2026-08-13
- Updated: 2026-08-26

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
4. Worker 使用 claim 结果创建全新的 Cursor SDK Agent 或 `codex exec` 会话。提示词只要求
   使用已安装的 `kanban-complete-tasks` Skill；Agent 通过 scoped MCP 的
   `get_current_card` 读取已冻结的卡片上下文，不再调用 `pick_next_card`。
5. token 不进入 AI 提示。每个临时端点只绑定本轮 cardId，并只暴露 scoped Agent 工具。
6. 每轮 claim 前，Worker 先 peek 下一张卡并合并覆盖，再在仓库目录执行
   `git status --short`。默认工作区不干净则不领取并停止批次；非 Git 目录则跳过检查。
   工作台或本卡可打开「允许脏工作区」（例如代码审查）；打开后脏工作区仍可领取。
   工作台关闭「允许使用卡片参数」时忽略本卡该开关及其它卡片覆盖（引擎、模型、参数、沙箱、测试要求）。
7. 工作台本机开关「收尾后主动结束会话」开启时，收尾工具成功落盘即可结束 Cursor SDK run 或 Codex 进程；关闭时，Cursor 以 `run.wait()` 的 `finished/error`、Codex 以独立进程退出码判断会话自然结束，不解析 AI 最终文字。默认开启。
8. 会话结束后，Worker 读取 pending 状态并执行私有校验、提交与 finalize；进入待验证才
   继续，进入阻塞或失败则按确定性状态处理。
9. Worker 再次 claim；空队列或达到上限时结束批次。
10. Agent 临时端点只暴露 `get_current_card`、`ready_to_submit`、
    `submit_consultation`、`block_card`。
    Worker 与 IDE 使用常驻完整工具目录及私有 dispatch 工具。
11. 实施卡由 Agent 调用 `ready_to_submit` 声明完成；Git 提交与送验由 Worker 驱动的
    两阶段 finalize 完成。Agent 不得自行 `git commit` 或移动 HEAD。对于卡片正文明确
    指定哈希的提交撤销，Agent 只能声明 `gitRevertCommit` 意图，由 Worker 受控执行。

## 实现约束

- scoped MCP 与完整目录共用 `/mcp` 路径，靠每会话临时端口区分。临时端口启动失败时
  不得回退完整工具目录。
- Cursor 与 Codex 默认只连接本卡 scoped `kanbanMCP`。用户/项目里的其它 MCP（Hub、
  Aseprite、Chrome DevTools、Tavily、Unity、Cocos、Node REPL 等）仅当当前项目在
  `ProjectSettings.agentMcpTags` 中配置对应标签时才合并；`kanbanMCP` 必须覆盖为本轮
  scoped 端点，不得使用常驻完整看板 MCP。
- Worker 不把 scoped 工具 schema、Skill 正文、Rule、Architecture、卡片正文或附件复制到
  本轮 prompt；工具通过正常 MCP catalog 暴露，提示词只调用 Skill。
- Cursor：SDK 的 `settingSources` 使用 `all`，加载与 Cursor 客户端一致的项目、用户、团队、
  MDM 与插件设置层，使 Rules / Skills / Hooks 使用相同的环境。MCP 仍由 Worker 按当前项目
  MCP 标签从用户/项目 `mcp.json` 筛选后注入，并覆盖 `kanbanMCP` 为本轮 scoped 端点。
- `kanban-complete-tasks` 是本流程唯一要求调用的 Skill，以磁盘内容为准；Worker 不读取、
  剥离、改写或注入 Skill 正文。
- Codex：临时 `CODEX_HOME` 复制用户 `auth.json` 和未改写的 `AGENTS.md`，并且只从
  `%USERPROFILE%\.cursor\skills` 复制 `kanban-complete-tasks`。按当前项目 MCP 标签筛选
  用户 `config.toml` 中的 MCP，再写入 scoped `kanbanMCP`。
- `get_current_card` 只能返回本轮原子领取时冻结的 cardId、cardKind、workMode、workItems、
  effectiveRequireTests 和附件内容，不得回读当前 UI 项目或用实时卡片扩大范围。
- 调度中 `get_current_card` / `ready_to_submit` / `block_card` / `submit_consultation` 只能操作
  本轮领取的卡片。
- `ready_to_submit` 根据 Worker 上报的 Shell 时间线拒绝：验证仍在执行、exitCode≠0、或 `flutter test` / `dart test` 成功但耗时过短（路径/cwd 错误或 SDK 秒退 completed）。Dart 与 Worker TypeScript 使用同一套判定。
- Worker 记录步骤、工具、重复工具与重复读取指标。
- 完整 MCP 在活跃锁下不得绕过锁定卡的 submit、block、move、complete、delete、
  commitRef、checklist 或 feedback 契约。
- claim 失败或空队列不占用本轮名额，且不得创建临时端点。
- finalize 按 ADR-007 处理 HEAD 相对 baseline 的漂移：baseline 的后代可软复位后由
  Worker 统一提交；无关历史仍拒绝。

## 结果

- AI 不控制批次循环，也不需要输出任何调度标记。
- Worker 原子领取卡片并获得本轮唯一端点，Agent 只处理 scoped MCP 返回的冻结范围。
- 每张卡片对应一次新的顶层 Agent 会话，端点与 cardId 一一绑定。
- 调度期间，完整 MCP 无法绕过本轮卡片锁或提前送验。
