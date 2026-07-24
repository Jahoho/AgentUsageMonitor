<p align="center">
  <img src="docs/assets/agent-usage-monitor-icon.png" width="128" height="128" alt="Agent Usage Monitor 图标">
</p>

<h1 align="center">Agent Usage Monitor</h1>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  看清还剩多少、花了多少，以及哪些用量数字真的可信。
</p>

<p align="center">
  <a href="https://github.com/Jahoho/AgentUsageMonitor/actions/workflows/ci.yml"><img src="https://github.com/Jahoho/AgentUsageMonitor/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14 或更高版本">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT License"></a>
</p>

AI Coding 往往不只有一种计费方式。一个开发者可能在同一天切换订阅制 Agent、按量计费的 API Key 和本地 Coding Session，而每个平台对“用量”的定义并不相同。

Agent Usage Monitor 用一个紧凑的原生 macOS 界面集中展示这些信号，但不会假装它们可以直接相加。订阅余量、API 支出和本地观测活动彼此分开；当可靠数据缺失时，会明确显示不可用，而不是给出看似精确的猜测。

当前公开分发仍以源码为主。仓库可以在本地构建和验证；Developer ID 签名及 Apple 公证是后续独立里程碑，不是当前版本的前置条件。

## 它帮助你做什么决定

- **准备开始一个长任务时：** 先查看当前 Official 额度和重置时间；只有同一周期证据足够时，才参考本地预测。
- **在多个工具之间切换时：** 快速判断当前活跃 Provider，并区分订阅容量、API 支出和本地观测 Token。
- **一个周周期结束后：** 回顾使用是安静、集中、稳定，还是多次接近上限，而不是再看一遍相同的百分比。
- **Provider 数据源失效时：** 明确知道当前值不可用，而不是被过期额度或虚构历史误导。

这个产品的目标不是制造一个统一的“AI 用量分数”，而是在保留每个数字真实计量方式和可信边界的前提下，帮助用户做更好的使用决策。

## Provider 支持

| Provider | 当前显示内容 | 数据来源 |
| --- | --- | --- |
| Codex | 当前额度、重置时间、reset credits、紧凑的本地额度预测，以及可展开的每周 recap | 当前官方 ChatGPT Codex API 或 Codex CLI RPC；预测和 recap 使用经过隐私隔离的本地官方样本 |
| Codex activity | 今日、滚动 30 天和每小时本地 Token 活动 | 本地 Codex session 日志中的明确用量字段 |
| Claude | Claude Code 安装状态和官方用量入口 | 本地 CLI 可用性；准确额度暂不可用 |
| DeepSeek | 账户余额 | 官方 `/user/balance` API |
| DeepSeek activity | 每个 Key 的 Token、模型、每小时活动，以及可严格定价的受支持请求 | 本地回环代理捕获的明确 usage 字段 |
| OpenRouter | Key 支出、限额和账户 credits | 官方 Key 与 credits API |
| OpenRouter activity | 托管 Key 名称、模型活动和已完成日期的每日用量 | 官方 management-key API |

包括 fallback 行为和已知数据源限制在内的详细说明，请参阅 [Data Sources](docs/DATA_SOURCES.md)（英文）。

## 产品原则

- **来源完整性。** Official、Observed、Estimated 和 Unavailable 不能互相替代。
- **失败时保持明确。** 当 Provider 没有返回当前可用的官方信息时，官方用量区域会显示错误；不会悄悄改用过期数据或合成数据。
- **本地控制。** API Key 保存在 macOS Keychain。项目没有托管后端、分析服务、广告 SDK 或由维护者运营的遥测端点。
- **原生体验。** 应用使用 SwiftUI 与 AppKit 构建，是一个轻量、紧凑、可自适应尺寸且不显示 Dock 图标的菜单栏工具。

## 系统要求

- macOS 14 Sonoma 或更高版本
- Xcode 16 或其他 Swift 6 工具链
- 从源码构建时支持 Apple Silicon 或 Intel Mac

本地打包脚本会为当前构建机器的架构生成二进制文件。项目暂未提供公开的 universal、已签名或已公证二进制包。

## 从源码构建

```bash
git clone https://github.com/Jahoho/AgentUsageMonitor.git
cd AgentUsageMonitor
swift test --no-parallel
swift run AgentUsageMonitor
```

启动后，应用会以仪表图标显示在菜单栏中。点击图标即可打开监控窗口。

构建并验证本地 `.app`：

```bash
./scripts/release-check.sh
```

安装已经验证的本地构建：

```bash
./scripts/install-app.sh
./scripts/verify-installation.sh
open /Applications/AgentUsageMonitor.app
```

运行安装器前，请先退出已启动的 Agent Usage Monitor。安装器会验证临时替换版本；如果替换验证失败，会恢复之前的应用。

## 配置

Provider 配置位于应用内的 `Settings`，详细说明见 [Configuration](docs/CONFIGURATION.md)（英文）。主要行为如下：

- Codex 复用现有的本地 Codex 登录状态，应用不会要求输入 ChatGPT 密码。
- DeepSeek 支持多个带名称的 Key，并可通过仅监听 `127.0.0.1:18491` 的可选回环代理捕获明确的 usage 数据。
- OpenRouter 支持多个带名称的 Key。Management Key 可以提供更多官方账户与 activity 数据。
- 在出现稳定、机器可读的官方订阅来源之前，Claude 会继续保持明确的有限支持状态。
- 额度预测只显示在具备可靠数据源的订阅 Coding Plan 平台详情页；Overview 和按量计费的 API Key 平台不会显示。

## 隐私与安全

Agent Usage Monitor 只读取已启用功能所需的 Provider 文件和凭据。派生用量历史保留在 Mac 本地，密钥不会写入项目日志或 JSON 元数据。

[Privacy](PRIVACY.md)（英文）说明了具体本地文件、网络目标、保留行为和清理步骤。安全问题请按照 [Security Policy](SECURITY.md)（英文）通过私密流程报告，不要创建公开 Issue。

## 开发

Swift Package 分为两层：

- `AgentUsageCore`：Provider-neutral models、纯解析器、置信度语义和聚合逻辑。
- `AgentUsageMonitor`：macOS UI、Provider adapters、网络、Keychain、本地进程集成和打包逻辑。

开发者可以从 [Documentation Index](docs/README.md)、[Architecture](docs/ARCHITECTURE.md) 和 [Contributing Guide](CONTRIBUTING.md) 开始阅读。完整发布命令会执行空白检查、仓库安全检查、全部自动化测试、干净的 Release 构建和应用包验证。

## 当前限制

- 应用尚未针对第三方二进制分发完成签名和 Apple 公证。
- 当前 Claude adapter 无法提供准确的订阅额度。
- Codex 本地 Token activity 是观测遥测，不是官方账户账单总量。
- Codex 额度预测只会在同一周期的 Official 历史足够时出现；样本稀疏或趋势不稳定时会保持不可用。
- Codex 每周 recap 需要一个可信的已完成周期；个人对比和描述性的 Plan fit 还需要更多历史周期。
- DeepSeek 历史 activity 只包含经过本应用代理的请求。
- OpenRouter Token activity 需要 Management Key，并且只反映官方 API 返回的记录。

完整覆盖门槛和失败规则见 [Data Sources](docs/DATA_SOURCES.md)（英文）。后续计划见 [Roadmap](docs/ROADMAP.md)（英文）。

## License 与商标

项目源码使用 [MIT License](LICENSE)。Provider 名称与 Logo 仅用于标识兼容服务，相关权利仍归各自所有者所有，详见 [Notices](NOTICE.md)。

Agent Usage Monitor 是独立项目，与 OpenAI、Anthropic、DeepSeek、OpenRouter 或 Apple 不存在附属、认可或赞助关系。
