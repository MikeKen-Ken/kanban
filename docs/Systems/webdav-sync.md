# WebDAV 同步与冲突处理

## 触发

- 本地改动后按 `pushDebounceSeconds` 防抖推送（默认 60s，范围 5–60s）；需开启 `autoSync`；本地立刻落盘，仅延迟云端请求；若处于失败/限流冷却，再延后到冷却结束
- 启动时拉取：仅当 `autoPull` 开启时执行一次 `pullAndMerge`
- 手动同步：先 `pullAndMerge`，有变更时再写回远端；**不受**拉取间隔与失败冷却限制，也不受 `autoSync` / `autoPull` 限制
- 后台轮询：按 `pollIntervalSeconds` 单次定时续期（默认 600s，范围 60–600s）；需开启 `autoPull`
- 保存 WebDAV 配置：只落盘并按需启停轮询，**不**自动触发同步
- 配置项：`WebDavConfig.enabled`、`autoSync`（自动上传）、`autoPull`（自动拉取）、`pollIntervalSeconds`、`pushDebounceSeconds`
- 仅手动：关闭 `autoSync` 与 `autoPull` 后，只有点「立即同步」才会 `pullAndMerge` / 上传

## 节流与退避

- 用「上次尝试时间」节流，失败也会拉开间隔（不再只认成功时间）
- 失败指数退避；识别 `429` / `toomanyrequests` 时从 60s 起跳，上限 10 分钟
- 自动轮询与进行中的同步重叠时直接丢弃，不立刻连环重试
- 合并结果与远端 JSON 一致时跳过 JSON 回推，减少无意义写入
- **增量推送**：相对 SyncBase（本地防抖推送）或相对刚拉取的远端（合并回推），只上传内容变化的 JSON 文件；未改项目/列/设置整文件跳过。附件仍按「本地有、远端无」补传。
- **增量拉取**：读远端 `sync_index.json`，与本地 SyncBase 内容指纹比对；一致则复用 SyncBase、不下载该 JSON。无索引或无 SyncBase 时全量拉取。

## 远端结构

根目录（默认 `/KanbanApp`）下：

- `projects.json` — 项目清单
- `app_trash.json` — 应用级回收站
- `shared_content.json` — 共享内容（标签等）
- `wallpapers/` — 工作区级壁纸原图与缩略图；下载后持久化到设备本地缓存，项目仅引用壁纸 id
- `sync_index.json` — 各 JSON 文件内容指纹（sha256）；拉取时与本地 SyncBase 比对，跳过未变更文件。旧客户端可忽略；无索引时回退全量拉取
- `projects/{projectId}/board.json` + `columns/*.json` + `settings.json` + `trash.json` + `attachments/`

## 进度

- `SyncProgress`：阶段（准备/拉取/合并/上传/附件/收尾）、已完成/总数、当前文件标签、跳过未变更文件数
- 顶栏同步中显示「同步中 3/12」；悬停可看阶段与当前文件
- **拉取增量**：优先读 `sync_index.json`；若与 SyncBase 指纹一致则跳过对应 JSON 下载（不依赖 WebDAV ETag）。附件仍按引用全量对齐（本地已有则跳过）
- 推送端：文件级增量上传；每次 JSON 推送成功后重写 `sync_index.json`

## 合并层级

合并入口：`features/sync_conflict/mergeWorkspaces`。

使用本地 **SyncBase**（上次成功同步后的工作区快照）做三路合并：`local` vs `base` vs `remote`。

| 实体 | 策略 |
|---|---|
| Manifest | 有 base 时传播删除：一侧缺且对侧相对 base 未改 → 采纳删除；对侧改过（条目或看板/设置内容）→ 挂 `conflictDeleted`；无 base 时按 id **并集**（避免误删离线新建）。同 id 标题冲突挂 `conflictTitle` |
| Board | 列 id 并集；列元数据 LWW；卡片见下 |
| Card | 非重叠字段自动合；同字段冲突 / 删改冲突 → `conflictSide` |
| Settings | 字段级合并；冲突挂 `conflictSide` |
| Trash | 按条目 id 并集；项目被采纳删除且回收站尚无快照时补写项目条目 |

合并结果相对远端有变更时再增量 push，避免并集内容只留在本机。SyncBase 在推送成功且本机快照未漂移后推进；若同步期间又有本地写入则排队再推。

## 冲突标记

- 卡片：`conflictSide`（另一侧完整快照）、`conflictColumnId`、`conflictDeleted`（删除意图）
- 看板：`conflictTitle`
- 项目条目：`conflictTitle`、`conflictDeleted`（删 vs 改）
- 设置：`conflictSide`

冲突字段会随 JSON 同步到 WebDAV，其它端可见。

## 用户解决

1. 看板卡片显示「冲突」角标与边框
2. 打开详情：保留当前 / 保留另一份（或确认删除）
3. `BoardController.resolveCardConflict` 清空冲突字段并 `bump` 后推送
4. 项目删改冲突：项目切换器显示「冲突」，可「保留项目」或「确认删除」（`resolveProjectConflict`）
5. 顶栏同步指示器显示未解决冲突数量与同步进度

## 明确不做（二期）

- WebDAV `If-Match` / ETag 条件写（冲突检测仍靠三路合并；拉取跳过已由 `sync_index` 覆盖）
- 每卡一文件布局
- 附件二进制内容冲突副本
- 附件「缺图再拉 / 打开卡片再下」（同步时仍按引用拉齐）
- AppSettings / 标签回收站上云
- CRDT

## 本地并发写入

- 磁盘与远端均按项目分文件：`projects/{projectId}/board.json` 等；共享面仅 `projects.json` / `shared_content.json` / `app_trash.json`。
- 进程内看板突变经 `BoardController` 的可重入 `AsyncMutex` 串行，避免 MCP `runOnProject` 临时切换内存上下文时与 UI 写交错导致写错项目或丢更新。
- **网络 I/O 不持突变锁**：仅捕获本地快照、合并落盘、推进 SyncBase 时短持锁；同步进行中 UI/MCP 可继续操作。
- 对外项目写操作期间不入撤销栈；同项目并发写为串行 last-writer 语义（无 CRDT）。
- 多设备远端仍依赖三路合并；拉取跳过依赖应用层 `sync_index`，未使用 WebDAV If-Match/ETag。
