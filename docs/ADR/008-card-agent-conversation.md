# ADR-008：卡片 Agent 多轮交互与同步对话

- Status: accepted
- Date: 2026-08-19

## 背景

原调度把一次 Agent run 结束等同于整张卡片的会话结束，并在结束后立即释放
Agent、scoped MCP 与 Worker。无头 Worker 也没有可供 `AskQuestion` 等能力等待用户
输入的通道。项目日志仅是本机调试输出，既不能回复，也不会通过 WebDAV 同步。

ADR-003 禁止把完整对话放进仅本机 MCP 运行上下文；ADR-006 则规定每卡一次新的
顶层会话。这两项仍适合机器恢复状态，但不足以承载用户明确要求的卡片对话。

## 决策

1. 卡片增加可选 `agentConversationMarkdown`，它是对话的权威文本，随卡片 JSON、
   SyncBase、三路合并、备份与 WebDAV 流转；缺失字段视为空，旧客户端可忽略。App
   同时维护名为 `Agent 对话.md` 的普通文件附件镜像，使用户可从卡片直接打开真实
   Markdown 文件；该附件沿用现有附件上传、下载和缺失提示。
2. 本机运行中的 Cursor Agent 使用 `ask_user` 自定义工具替代无头 `askQuestion`。
   工具通过 Worker 临时目录与 App 交换一次性 request/reply 文件，等待期间不释放
   Agent、scoped MCP 或卡片锁，回复后在同一个 Agent 实例继续。
3. Worker 通过独立的结构化 stdout 协议上报会话、助手消息和提问。App 是卡片对话
   Markdown 及附件镜像的唯一持久化入口；临时 request/reply 文件不进入工作区、备份
   或 WebDAV。
4. 已结束卡片的追问追加到 Markdown，并新增一条未完成验证反馈，使卡片进入待返工。
   下一次正常 Worker claim 会把既有 Markdown 随冻结卡片上下文注入新会话，但本轮
   `workItems` 只含未完成验证反馈，不再把卡片最初的标题与备注当作当前任务。跨设备
   恢复依赖 Markdown，而不依赖本机 Cursor agentId。
5. 对话记录不保存密钥、Worker token、scoped endpoint、临时附件路径或完整
   tool 输出。保存用户消息、面向用户的助手消息，以及模型思考过程（Markdown
   `### 思考`）。思考来自 Cursor `thinkingMessage` / 思考流与 Codex `reasoning`
   条目；工具调用仍只进本机 Worker 日志。
6. Codex `exec` 当前仍是单次非交互进程：它上报并同步会话结果，运行后追问通过待返工
   新会话恢复 Markdown 上下文。进程内暂停问答仅在支持自定义等待工具的 Cursor SDK
   路径启用。

## 对既有 ADR 的修订

- ADR-003 的“运行上下文不保存完整对话”继续成立；本 ADR 的 Markdown 属于卡片用户
  内容，不属于 MCP 本机运行上下文。
- ADR-006 的“每张卡片对应一次新的顶层 Agent 会话”改为“每次 claim 对应一个顶层
  Agent 会话”；同一 claim 内可多轮 send/工具等待，历史追问则通过新的待返工 claim
  恢复。

## 结果

- 运行中的澄清可暂停并在同一 Cursor 会话继续，不再把问题误判为任务失败。
- 卡片详情提供统一的查看、回复与后续追问入口。
- 对话可随现有 WebDAV 工作区同步，另一设备无需复制本机 Agent 存储即可查看并续问。
- 同一 Markdown 字段在多设备同时编辑时使用既有卡片字段冲突机制，不引入 CRDT。
