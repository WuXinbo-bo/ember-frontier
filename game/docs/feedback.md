# 已确认的 Engine / SDK 文档问题

## 2026-11-11 · 0.4.19 SDK 引导文档链接失效

生成 AGENTS.md 指向公开仓库 main 下的 `docs/engine/skills/forgeax-engine-sdk/references/game-project-guide.md`。按该链接读取 raw 内容返回 HTTP 404。工程保留原始生成指南；实际 API 以同版 SDK 的源码包 README、生成的 API index 和 CLI help 为依据，不把失效文档当成已读。

环境：macOS arm64、Node 24.22.1、工程 pnpm 12.15.0。

## pnpm 12 工作区模式校验
Engine 0.4.19 `project check` 将未声明 packages 解析为 []，而 pnpm 12.15.0 安装后记录 ["."]，导致 workspace-state-stale。工程显式声明 packages: ["."] 并重新安装后复核；不改 SDK 或生成状态。
