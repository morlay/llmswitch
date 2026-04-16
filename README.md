# LLMSwitch

LLMSwitch 是一个面向 macOS 的本地 LLM 路由与切换工具，可以理解成一个 `openrouter for local`。

它在本地提供 OpenAI 兼容入口，聚合多个上游 LLM Provider，并通过 CLI 与 macOS 状态栏应用管理模型绑定、可用性和运行状态。

当前项目主要解决这些事情：

- 在本地暴露统一的 LLM 访问入口。
- 聚合多个 Provider，并按本地规则暴露可用模型。
- 支持同名模型在不同 Provider 之间切换绑定。
- 通过状态栏应用管理 Provider、模型开关和运行状态。
- 以尽量轻量的 Swift 技术栈完成本地代理与桌面交互。

更多信息：

- 目录与入口分层见 [LAYOUT.md](LAYOUT.md)。
- 协作约束见 [AGENTS.md](AGENTS.md)。
- 命令入口见 [justfile](justfile)，直接运行 `just --list --list-submodules`。
