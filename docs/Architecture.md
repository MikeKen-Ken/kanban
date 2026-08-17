# 系统架构

## 产品边界

本项目是面向个人使用的 Windows 与 Android 跨平台看板。核心能力是多项目、列式任务流、本地优先存储和 WebDAV 多设备同步。

明确不包含账号、团队成员、实时协作与 CRDT。其他平台只需避免破坏既有条件编译，不作为当前功能验收目标。

## 分层

```text
界面层 screens/widgets/features/*/ui
  ↓
功能层 features/*（查询、命令、调度、导入导出）
  ↓
应用编排 controllers/BoardController
  ↓
仓储与同步 storage/ + webdav_sync/ + features/sync_conflict/
  ↓
本地 JSON / SharedPreferences / WebDAV
```

- 界面层只负责展示状态和转发用户意图，不持有流程权威状态。
- 功能模块对外暴露少量模型、服务或页面入口；内部实现保持在自身目录。
- `BoardController` 负责跨模块编排，不承载可独立测试的筛选、日期、重复、统计或解析算法。
- 两个以上功能共同使用的纯工具放入 `app/lib/common/`。
- 存储和同步层不得依赖具体界面。

## 数据所有权

### 同步的用户内容

- 项目清单、看板、列、卡片、项目设置与回收站
- 看板背景图（工作区级 `SharedContent.wallpapers` 元数据 + 根级 `wallpapers/` 文件；项目设置仅保存引用与轮播策略）
- 图片附件
- 自定义标签
- 保存视图
- 卡片模板
- 活动历史
- WIP 配置
- 提醒时间与重复规则
- 卡片外链、依赖与关联
- 卡片 Agent 覆盖（引擎、模型、参数、是否允许脏工作区）
- 泳道分组与自动化规则

同步内容使用可选 JSON 字段或独立文件扩展。旧客户端必须能够忽略未知字段，新客户端读取缺失字段时必须使用安全默认值。

### 仅本机数据

- WebDAV 凭据
- 当前项目
- 明暗模式、拖拽延迟、引导状态等界面偏好
- Windows 内嵌 MCP 开关与端口
- Agent 调度偏好（引擎、仓库路径、模型、思考程度、是否禁止使用卡片参数、是否允许脏工作区等）
- Agent 调度 pending 收尾事务与提交范围快照（仅本机 SharedPreferences，不进入工作区 JSON / WebDAV）
- MCP 代理运行上下文（按项目与卡片保存的 sub-agent / Git 恢复信息）
- 撤销栈
- 系统通知调度记录
- SyncBase

## 主要数据流

### 本地修改

```text
用户操作
  → 功能命令
  → BoardController 编排
  → 本地立即持久化
  → 更新界面
  → 不自动上传；仅用户选择上传 / 下载 / 合并
```

### 远端同步

```text
上传：全量推送本机工作区，覆盖云端（需二次确认）
下载：全量拉取云端工作区，覆盖本机（需二次确认）
合并：拉取远端 → local/base/remote 三路合并 → 写入冲突标记 → 本地落盘 → 有差异时再写回远端
```

## 功能目录

新增功能放在 `app/lib/features/<feature>/`：

- `views/`：今日、日历、全局查询、组合筛选和保存视图
- `quick_capture/`：快速录入与自然语言解析
- `undo/`：可撤销命令与本机撤销栈
- `templates/`：卡片模板与复制
- `reminders/`：提醒、重复规则和平台调度
- `agent_dispatch/`：桌面端本机批量调度 Cursor SDK / Codex exec；Windows 发布包内置 Worker，API Key 使用系统安全存储（仅本机）
- `mcp/`：Windows 内嵌 MCP 与 Cursor/Codex 一键配置（仅本机）
- `statistics/`：只读统计
- `wip/`：列上限策略
- `activity/`：活动事件、持久化与合并
- `import_export/`：完整备份、校验与导入
- `labels/`：共享自定义标签管理
- `onboarding/`：首次引导
- `app_update/`：从 GitHub Release 检查/下载更新（Android APK 安装；Windows zip 同目录覆盖重启）
- `automations/`：项目内自动化规则（触发 → 动作）
- `kanban/`：列/卡片展示、泳道分组、详情编辑

跨功能日期判断、标识符和结果类型放在 `app/lib/common/`。

## 同步扩展约束

新增或修改同步字段时必须同时检查：

1. `toJson` / `fromJson` 与默认值
2. 内容相等判断
3. 三路字段合并
4. SyncBase 快照
5. WebDAV 上传与下载清单
6. 冲突数量与解决界面
7. 旧数据与旧端兼容测试

追加型活动历史按事件 ID 并集合并。重复任务生成下一期时使用稳定系列标识和周期键，确保多设备幂等。

## 验证

- 纯算法使用单元测试。
- 存储和同步使用模型、合并与集成测试。
- Windows 快捷键、右键菜单和通知需要平台验证。
- Android 通知权限、TalkBack、窄屏布局与长按拖拽需要平台验证。
- 人类开发阶段与 CI：至少运行 `flutter analyze` 和相关测试；最终运行全部测试与 Windows/Android 构建。
- Agent 在会话内跑与本卡改动直接相关的定向检查，通过后才能声明完成；不要把测试命令交给 Worker 代跑，也不要把上一条的全量 `flutter analyze` / 全量测试当作默认收尾。卡住、超时不得当成通过；未做的 UI 验证须标明未执行。
