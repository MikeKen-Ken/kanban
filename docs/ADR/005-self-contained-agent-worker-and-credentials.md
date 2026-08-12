# ADR-005：自包含 Agent Worker 与本机凭据

- Status: accepted
- Date: 2026-08-12

## 背景

Windows 发布包只包含 Flutter `Release` 目录，Agent 调度却从源码仓库的
`scripts/agent_dispatch` 查找 Worker，并在用户机器上运行 `npm install` 与构建。
普通用户下载 ZIP 后没有源码目录，因此“一键修复 Worker”必然失败。Cursor SDK
还要求 API Key，但界面没有配置入口，桌面客户端登录也不会自动提供 SDK 凭据。

## 决策

1. Windows 发布包在可执行文件同级携带 `agent_worker/`，其中包含已构建 CLI、
   Cursor SDK、官方 Codex CLI、生产依赖和匹配版本的便携 Node.js；正常运行不依赖
   用户安装 Node/npm、独立 Codex CLI 或源码仓库。
2. Worker 路径优先允许显式覆盖和 `KANBAN_ROOT` 开发覆盖，再查找可执行文件同级
   的内置目录；当前工作目录探测仅作为开发兼容路径。
3. Cursor API Key 使用系统安全存储保存，只在启动 Worker 子进程时通过环境变量
   注入；不得进入 SharedPreferences、日志、任务数据、备份、WebDAV 或 job JSON。
4. 已存在的 `CURSOR_API_KEY` 环境变量继续作为兼容回退，但界面不展示其内容。
5. Codex 优先调用 Worker 内置的官方 Codex CLI，并复用 `codex login` 缓存；缺少
   内置 CLI 时才回退到 PATH，不在看板中保存 OpenAI API Key。
6. “一键修复 Worker”首先验证内置运行时；开发包缺依赖时才回退到 npm 修复。

## 结果

- Windows ZIP 解压后即可检测并运行 Worker；Cursor 只需配置自己的 API Key，
  Codex 只需已有可复用的本机登录。
- 发布流程必须验证 `dist/cli.js`、`@cursor/sdk` 与便携 `node.exe` 均存在。
- API Key 属于仅本机敏感凭据，删除应用普通偏好不会泄露或同步它。
