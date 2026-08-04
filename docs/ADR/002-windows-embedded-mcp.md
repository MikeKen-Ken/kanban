# ADR-002：Windows 内嵌 MCP 与一键客户端配置

- Status: accepted
- Date: 2026-08-04

## 背景

希望本机 AI（Cursor、Codex）能读取与操作看板任务。数据权威在应用内的 `BoardController`，不宜另起进程直接改 JSON。

## 决策

1. **仅 Windows**：应用进程内嵌 Streamable HTTP MCP，默认绑定 `127.0.0.1`，路径 `/mcp`，默认端口 `18765`（避开常见 8080）。
2. **写入路径**：MCP 工具调用必须经 `BoardController`，复用落盘与 WebDAV 防抖，不旁路存储。
3. **服务名**：客户端配置键为 `kanbanMCP`。
4. **一键配置（反向）**：应用写入用户全局配置并 upsert，不覆盖其他 MCP：
   - Cursor：`%USERPROFILE%\.cursor\mcp.json`
   - Codex：`%USERPROFILE%\.codex\config.toml`（并确保 `features.rmcp_client = true`）
5. **本机偏好**：`mcpEnabled` / `mcpPort` 仅存 SharedPreferences，不同步。
6. **Android / 其他平台**：不启动服务；设置入口可隐藏或只读说明。

## 结果

- 打开看板即可对外提供 MCP；一键配置后重启客户端即可连接。
- 与 Unity MCP 的「服务端写客户端配置」模式一致，但使用独立端口与服务名，互不覆盖。
- 工具面覆盖任务/列/项目 CRUD、组合查询与保存视图、标签、模板、快速捕获、统计、活动、回收站与撤销；不含同步冲突解决与附件二进制。
