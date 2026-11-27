# WebDAV 同步与冲突处理

## 触发

- **自动同步默认关闭**：在设置页开启后，应用启动、返回前台、本地改动后防抖（默认 60s，遵循 `WebDavConfig.pushDebounceSeconds`），以及应用运行时定期（默认 10 分钟，遵循 `WebDavConfig.pollIntervalSeconds`）执行三路合并。应用关闭后没有后台同步任务。
- **上传**：全量打包当前本机工作区（JSON + 附件 + 标签回收站）为 `workspace.kanban-backup` 覆盖云端；覆盖前需二次确认
- **下载**：全量拉取云端 `workspace.kanban-backup` 并覆盖本机，不合并、不回推；云端无数据时失败并保留本机
- **合并**：`pullAndMerge`：三路合并后，有变更再回推 `workspace.kanban-backup`；**不受**冷却限制
- **壁纸上传 / 下载**：单独同步工作区壁纸库压缩包 `wallpapers.kanban-backup`（与主包分离，避免每次改卡片重传壁纸）；覆盖前需二次确认
- 保存 WebDAV 配置：开启自动同步时立即尝试合并并启动应用内定时器；关闭时停止定时器；切换服务器地址或远端路径时自动清理旧 `SyncBase` 基线
- 配置项：`WebDavConfig.enabled`、`autoSync`、`pollIntervalSeconds`、`pushDebounceSeconds`；`autoPull` 保留兼容字段

## 节流与退避

- 用「上次尝试时间」节流，失败也会拉开间隔（不再只认成功时间）
- 失败指数退避；识别 `429` / `toomanyrequests` 时从 60s 起跳，上限 10 分钟
- 手动同步 / 壁纸同步进行中再触发操作会排队，结束后按序执行
- **拉取短路**：先仅捕获本机 JSON 与 `labelTrash` 并比对远端 `workspace.complete.json`（含 `sha256`、`SyncBase` 与本机缺失附件检查）；命中一致时直接跳过包下载与全量附件读盘
- **合并回推判定**：合并结果相对远端在工作区 JSON、`labelTrash` 或裁剪后的附件集合有差异时才回推；从旧版分文件树迁移时补齐live包并仅在首次清理旧树
- **写入原子性**：上传实时归档时先写临时文件再 `MOVE` 覆盖（不支持 `MOVE` 覆盖的服务器回退直写），全程不提前删除 `complete.json`，避免并发读端误判云端为空库

## 远端结构

根目录（默认 `/KanbanApp`）下：

- `workspace.kanban-backup` + `workspace.complete.json` — 实时工作区归档包及其完成校验标记（含工作区 JSON、`label_trash.json` 与各项目附件）
- `wallpapers.kanban-backup` + `wallpapers.complete.json` — 工作区壁纸库压缩包及其完成校验标记
- `backups/{backupId}/archive.kanban-backup` + `complete.json` — 时间点备份快照
- 旧版分文件树（`projects.json`、`app_trash.json`、`shared_content.json`、`sync_index.json`、`projects/`）：拉取时仍保持向后兼容读取；迁移到 live 归档后按远端作用域仅清理一次

## 进度

- `SyncProgress`：阶段（准备/拉取/合并/上传/附件/收尾）、已完成/总数、当前文件标签、跳过未变更文件数
- 顶栏同步中显示「同步中 3/12」；悬停可看阶段与当前文件

## 合并层级

合并入口：`features/sync_conflict/mergeWorkspaces`。

使用本地 **SyncBase**（上次成功同步后的工作区快照，按远端地址与路径隔离）做三路合并：`local` vs `base` vs `remote`。

| 实体 | 策略 |
|---|---|
| Manifest | 有 base 时传播删除：一侧缺且对侧相对 base 未改 → 采纳删除；对侧改过（条目或看板/设置内容）→ 挂 `conflictDeleted`；无 base 时按 id **并集**（避免误删离线新建）。同 id 标题冲突挂 `conflictTitle` |
| Board | 有 base 时传播列删除（对侧未改列元数据且无合并后卡片留在该列 → 采纳删除；否则保留）；无 base 时列 id 并集；列元数据 LWW；卡片见下 |
| Card | 非重叠字段自动合（含 `order` 三路合）；同字段冲突 / 删改冲突 → `conflictSide`；若 `base` 已有冲突且一侧已解决而另一侧未改，直接采纳已解决结果避免冲突复活 |
| Settings | 字段级合并；冲突挂 `conflictSide` |
| Trash | 按条目 id 并集（含 `labelTrash`）；项目被采纳删除且回收站尚无快照时补写项目条目 |
| Attachments | 合并后按实际引用集合裁剪孤儿附件，避免已删除卡片的附件在包内复活 |

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
