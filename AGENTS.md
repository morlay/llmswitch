# AGENTS

本文件只保留通用协作约束，不重复项目实现细节。

## 文档分工

- [README.md](README.md) 只写项目介绍。
- [AGENTS.md](AGENTS.md) 只写通用约束、协作约定和维护规则。
- [LAYOUT.md](LAYOUT.md) 只写 monorepo 目录约定、`cmd` / `macosapp` / `swiftpkg` / `tool` 边界和 just 入口分层。
- [justfile](justfile) 只写执行入口；需要查命令时直接运行 `just --list --list-submodules`。
- [TASK_STATUS.md](TASK_STATUS.md) 只跟踪阶段目标和任务状态。

## 通用约束

- 优先沿用现有技术栈和目录结构，除非有明确理由再引入新依赖或新运行时。
- 命名使用业务语义，不使用占位式前缀或临时命名。
- 公共交互、公共样式和公共操作优先拆成可复用组件，不把页面持续堆回单文件。
- 不在多个文档里重复同一类信息；内容应归到对应入口维护。

## 维护规则

- 修改项目介绍时同步更新 [README.md](README.md)。
- 修改 monorepo 目录组织、模块入口或 just 分层时同步更新 [LAYOUT.md](LAYOUT.md)。
- 修改构建、安装、测试、调试入口时同步更新 [justfile](justfile)，并保持 `just --list --list-submodules` 可读。
- 修改阶段计划或完成状态时同步更新 [TASK_STATUS.md](TASK_STATUS.md)。
