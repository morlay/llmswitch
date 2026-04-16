# Task Status

## Current Goal

- 按 feat_01 重构配置与设置体验
- 去掉 env 方案，补本地入口 apiKey 认证
- Provider / Model 切换改成结构化表单

## Done

- [x] 需求拆分文档
- [x] 按 LAYOUT 拆分 monorepo 目录
- [x] Swift core package
- [x] 配置 / 状态 / 缓存 / 模型注册
- [x] 最小本地 HTTP 代理服务
- [x] 基础测试通过

## In Progress

- [x] 菜单栏 app target
- [x] app 内状态展示和最小操作
- [x] debug `.app` 打包脚本
- [x] debug 安装脚本
- [x] provider 刷新入口
- [x] 本地入口 apiKey 认证
- [x] displayName 可选并回退到 provider name
- [x] Provider 级模型开关
- [x] Models Switch 分组切换
- [x] Provider 新增 / 编辑 / 删除表单
- [x] 状态栏显示 enabled providers 健康状态
- [x] 移除 env 特性和 env.toml 方案
- [x] Settings 移除 Models Switch 独立区域
- [x] 紧凑布局 + icon buttons + 绿点/灰点状态
- [x] 启动先监听本地端口再异步刷新模型
- [x] 本地 proxy curl 可访问性脚本
- [x] service apiKey mask / unmask 交互
- [x] 状态栏面板布局收紧与 Quit 二次确认
- [x] 菜单栏与设置页 UI 组件化拆分
- [x] Providers-only 管理窗口与具名 IconButton 组件
- [x] 文档入口归并到 AGENTS / README / justfile

## Next

- [x] 菜单栏 app 接管服务启动/停止
- [x] settings 面板
- [x] 配置编辑体验
- [x] app 内展示已启用模型和当前绑定
- [x] app 内模型 provider 切换
- [ ] provider 健康状态自动刷新
- [ ] 模型特性信息 richer decode
