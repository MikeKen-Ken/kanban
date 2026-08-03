# WebDAV 同步与冲突处理

## 触发

- 本地改动后按 `pushDebounceSeconds` 防抖推送（默认 10s，范围 5–60s）；本地立刻落盘，仅延迟云端请求；若处于失败/限流冷却，再延后到冷却结束
- 启动 / 手动同步：先 `pullAndMerge`，有变更时再写回远端；**手动同步不受**拉取间隔与失败冷却限制
- 后台轮询：按 `pollIntervalSeconds` 单次定时续期（默认 120s，范围 60–600s）
- 配置项：`WebDavConfig.enabled`、`autoSync`、`pollIntervalSeconds`、`pushDebounceSeconds`

## 节流与退避

- 用「上次尝试时间」节流，失败也会拉开间隔（不再只认成功时间）
- 失败指数退避；识别 `429` / `toomanyrequests` 时从 60s 起跳，上限 10 分钟
- 自动轮询与进行中的同步重叠时直接丢弃，不立刻连环重试
- 合并结果与远端 JSON 一致时跳过全量 push，减少无意义写入

## 远端结构

根目录（默认 `/KanbanApp`）下：

- `projects.json` — 项目清单
- `app_trash.json` — 应用级回收站
- `projects/{projectId}/board.json` + `columns/*.json` + `settings.json` + `trash.json` + `attachments/`

## 合并层级

合并入口：`features/sync_conflict/mergeWorkspaces`。

使用本地 **SyncBase**（上次成功合并后的工作区快照）做三路合并：`local` vs `base` vs `remote`。

| 实体 | 策略 |
|---|---|
| Manifest | 有 base 时传播删除：一侧缺且对侧相对 base 未改 → 采纳删除；对侧改过（条目或看板/设置内容）→ 挂 `conflictDeleted`；无 base 时按 id **并集**（避免误删离线新建）。同 id 标题冲突挂 `conflictTitle` |
| Board | 列 id 并集；列元数据 LWW；卡片见下 |
| Card | 非重叠字段自动合；同字段冲突 / 删改冲突 → `conflictSide` |
| Settings | 字段级合并；冲突挂 `conflictSide` |
| Trash | 按条目 id 并集；项目被采纳删除且回收站尚无快照时补写项目条目 |

合并结果相对远端有变更时再 push，避免并集内容只留在本机。

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
5. 顶栏同步指示器显示未解决冲突数量

## 明确不做（二期）

- WebDAV `If-Match` / ETag
- 附件二进制内容冲突副本
- AppSettings / 标签回收站上云
- CRDT
