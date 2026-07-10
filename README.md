# Surge Relay

Surge Relay 是一个仅面向 macOS 26 的 SwiftUI 模块管理工具。App 管理多个 Loon、Quantumult X 或 Surge 来源，同时生成总模块与各来源的独立模块。设备可只订阅总模块的 GitHub Raw 地址，Mac mini 离线时仍可继续使用最后一次发布版本。

## 使用教程

- [从零配置 GitHub 私有仓库与 Cloudflare Worker](docs/GitHub-Cloudflare-Guide.md) — 面向新手的图文教程，包含 Token 权限、Worker 配置、验证方法和常见错误。

## 第一版能力

- 新增、编辑、删除和批量更新模块来源。
- 直接拖动模块调整顺序；越靠上的来源优先级越高，并在总模块的同一配置段中越靠前。
- 批量粘贴普通地址、现有 Script-Hub 转换地址或 Surge 安装地址，并自动还原原始来源。
- 在 App 内通过 JavaScriptCore 执行 Script-Hub 转换，Surge 无需安装 Script-Hub 模块。
- 添加或编辑模块时可展开“高级”，使用 Script-Hub 的名称、重写、策略、MitM、脚本名、超时、引擎、定时任务和参数等转换选项。
- 启用 Script-Hub 的脚本转换时，App 会预先生成并发布辅助 JavaScript 文件；设备仍只维护总模块这一个订阅。
- 自动检查 Script-Hub 官方模块引用的全部解析脚本，下载并原子更新 App 私有缓存。
- `.sgmodule` 来源直接下载合并，不经过 Script-Hub。
- 自动识别来源或转换结果中的 `#!icon` 元数据并缓存模块图标；没有图标时显示中性灰占位图标。
- 合并时移除 `#!system` 以及 requirement 中的设备/系统限制，同时保留核心版本要求。
- 每个来源带稳定标记、App 启停状态和总模块参数开关。
- 添加、编辑、启停或调整来源后自动刷新并重建，无需手动点击“重建总模块”。
- 每个来源保留独立的上次成功缓存；单项失败不会破坏整份总模块。
- 输出到 Surge 的 iCloud Drive 目录，便于本地调试。
- 通过 GitHub Contents API 同时发布总模块、每个来源的独立模块，以及自动引用的可选辅助脚本资源。
- GitHub Token 仅存储在 macOS 钥匙串。
- 定时刷新、自动发布、登录启动。
- 使用系统原生分栏与控件，并限制窗口最小尺寸以避免窄窗口破坏布局。

## 首次运行

1. 用 Xcode 26.6 或更新版本打开 `Surge Relay.xcodeproj`。
2. 运行 App。
3. 添加或批量导入原始模块地址并执行“更新全部”。
4. 如需多设备稳定订阅，在“GitHub 发布”中填写仓库信息和 Fine-grained Token。Token 需要目标仓库的 `Contents: Read and write` 权限。
5. 首次发布后，只安装总模块的稳定地址。

默认输出目录：

`~/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents/Surge Relay`

## Script-Hub 说明

项目文件不静态复制 Script-Hub 的转换器。App 运行时从官方仓库下载并缓存上游脚本，再通过 JavaScriptCore 执行；这些脚本仍适用 Script-Hub 的 GPL-3.0 许可。详见 `THIRD_PARTY_NOTICES.md`。

上游项目：[Script-Hub-Org/Script-Hub](https://github.com/Script-Hub-Org/Script-Hub)
