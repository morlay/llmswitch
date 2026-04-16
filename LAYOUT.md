# LAYOUT

本文件只说明 monorepo 目录约定、模块边界和 just 入口分层。

## 目录骨架

```text
cmd/
    {name}/
        Package.swift
    justfile
macosapp/
    {name}/
        Package.swift
    justfile
swiftpkg/
    {name}/
        Package.swift
tool/
    swift/
        justfile
```

## 入口分层

- 根入口在 [justfile](justfile)。这里只注册模块和项目级入口，不重复转发子模块已有 recipe。
- CLI 统一入口在 [cmd/justfile](cmd/justfile)。这里负责 command package 的 `build cmd`、`run cmd`。
- macOS app 统一入口在 [macosapp/justfile](macosapp/justfile)。这里负责 `build app`、`install app`、`restart app`。
- Swift toolchain 通用入口在 [tool/swift/justfile](tool/swift/justfile)。这里负责 `build`、`test`、`run`、`show-bin-path`。
- Swift package 只有在存在独有行为时才保留 `swiftpkg/{name}/justfile`。纯库 package 不放 justfile，直接复用 [tool/swift/justfile](tool/swift/justfile)。

## 当前模块

- [cmd/llmswitch](cmd/llmswitch) 是当前 CLI command package。
- [macosapp/LLMSwitch](macosapp/LLMSwitch) 是当前 macOS app package。
- [swiftpkg/LLMSwitchCore](swiftpkg/LLMSwitchCore) 是当前 Swift package，承载纯 core library。

## 命令形态

- `just cmd run llmswitch serve`
- `just macosapp build LLMSwitch`
- `just macosapp install LLMSwitch`
- `just macosapp restart LLMSwitch`
- `just swift test cmd/llmswitch`
- `just swift test swiftpkg/LLMSwitchCore`
