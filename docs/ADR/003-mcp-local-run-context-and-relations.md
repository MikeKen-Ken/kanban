# ADR-003：MCP 本机运行上下文与原子卡片关联

- Status: accepted
- Date: 2026-08-10

## 背景

代理执行任务时需要保存 sub-agent ID、Git 基线、恢复状态和交接摘要。这些字段只在当前设备与客户端会话中有效，不应写入卡片正文或通过 WebDAV 同步。合并任务还需要建立父卡与成员卡的双向关联；连续调用两次普通卡片更新会产生只写入一侧的中间状态。

## 决策

1. MCP 运行上下文按 `projectId + cardId` 保存到本机 `SharedPreferences`，不进入工作区 JSON、SyncBase、备份或 WebDAV。
2. 只通过受限的 `get_run_context`、`save_run_context`、`delete_run_context` 工具访问运行上下文；不开放任意本地文件读写，也不保存密钥或完整对话。
3. 卡片正文只保存用户可读的目标、结果、验证和风险；机器恢复字段不写入卡片。
4. 双向关联通过 `link_cards` / `unlink_cards` 调用 `BoardController` 原子更新两张卡，一次落盘并复用撤销、活动记录与同步路径。
5. `relatedIds` 仍属于同步的用户内容；本 ADR 不新增同步字段，也不改变现有三路合并格式。

## 结果

- 跨设备不会传播无效的本机 agent ID 或 Git 会话状态。
- 卡片说明更适合用户阅读，运行恢复仍可由本机 MCP 完成。
- 合并父卡与成员卡不会因中途失败留下单侧关联。
- 删除应用本机偏好会丢失运行上下文，但不会影响卡片、关联或实际交付物。
