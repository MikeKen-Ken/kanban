# WebDAV 同步与冲突处理

## 触发

- 本地改动后防抖推送（约 1.5s）
- 启动 / 轮询 / 手动同步：先 `pullAndMerge`，再写回远端
- 配置项：`WebDavConfig.enabled`、`autoSync`、`pollIntervalSeconds`

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
| Manifest | 按项目 id **并集**；同 id 标题冲突挂 `conflictTitle` |
| Board | 列 id 并集；列元数据 LWW；卡片见下 |
| Card | 非重叠字段自动合；同字段冲突 / 删改冲突 → `conflictSide` |
| Settings | 字段级合并；冲突挂 `conflictSide` |
| Trash | 按条目 id 并集 |

合并完成后 **始终 push** 合并结果，避免并集内容只留在本机。

## 冲突标记

- 卡片：`conflictSide`（另一侧完整快照）、`conflictColumnId`、`conflictDeleted`（删除意图）
- 看板：`conflictTitle`
- 项目条目：`conflictTitle`
- 设置：`conflictSide`

冲突字段会随 JSON 同步到 WebDAV，其它端可见。

## 用户解决

1. 看板卡片显示「冲突」角标与边框
2. 打开详情：保留当前 / 保留另一份（或确认删除）
3. `BoardController.resolveCardConflict` 清空冲突字段并 `bump` 后推送
4. 顶栏同步指示器显示未解决冲突数量

## 明确不做（二期）

- WebDAV `If-Match` / ETag
- 附件二进制内容冲突副本
- AppSettings / 标签回收站上云
- CRDT
