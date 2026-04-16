这是一个 macOS 状态栏工具

- 配置不同的 llm providers
    - 配置存储地址 `~/.config/llmswitch/config.toml`
    - `providers.{name}`
        - `displayName`:
        - `baseUrl`:https/http 都应该支持
        - `apiKey`: 直接填写或 env:LLM_API_KEY 动态读取
    - 通过 /v1/models 获取各自的支持列表
        - 但需要允许用户开关可用模型（作为常用模型）
    - 用户状态另行设计文件放在 `~/.config/llmswitch`, 不要回写 `config.toml`
    - 提供一个 settings UI 面板，管理上述功能
- 将所有用户选中的可用模型在状态栏展示，同名模型只支持使用其中一个供应商，状态栏上可切换
- 提供一个服务 (端口可配置)，提供 openai 完全兼容的 api
    - 当请求来时，通过匹配模型，转发到不同的供应商的对应模型，并使用对应的 `apiKey`，不做其他额外处理，不做统计

