# Surge Relay (macOS)

<p align="center">
  <img width="160" alt="Surge Relay Icon" src="https://github.com/user-attachments/assets/3672fe08-3217-41f8-a592-9a4f473b216b" />
</p>

<p align="center">
  一款用于集中管理、转换、编辑和发布 Surge 模块的 macOS 应用程序。
</p>

<p align="center">
  基于 <a href="https://github.com/Script-Hub-Org">Script-Hub</a> 的本地转换能力构建。
</p>

Surge Relay 适合需要同时维护大量 Surge 模块的用户，尤其是经常通过 Script-Hub 将 Loon、Quantumult X 或其他代理工具格式转换为 Surge `.sgmodule` 的场景。

它的目标是将模块转换、地址维护、规则编辑和多设备同步集中到一台 Mac 上完成。你只需要在 Surge Relay 中维护上游地址和转换规则，最终生成的 Surge 模块会被发布到稳定的分发地址，所有设备只需要订阅这些固定 URL。

## 预览

<p align="center">
  <img width="760" alt="Surge Relay Preview" src="https://github.com/user-attachments/assets/aee0f362-146d-4bbf-9069-b6fda1f8f886" />
</p>

## 特性

### 1. 集中化模块管理

在传统流程中，如果上游作者修改了仓库地址、文件路径或目录结构，用户通常需要重新打开 Script-Hub，重新转换模块，再重新安装到 Surge。

对于拥有多台设备的用户来说，这个过程需要在每台设备上重复操作。即便通过 iCloud 同步，也依然需要多次点击安装，维护成本很高。

Surge Relay 将这些流程集中到一台 Mac 上完成。你只需要在 App 中维护上游地址、备用地址和转换规则，Surge 设备端无需关心原始模块来源。

<p align="center">
  <img width="375" alt="Surge Relay Module Editor" src="https://github.com/user-attachments/assets/444cbc3d-d4b8-4047-a569-607692123503" />
  <img width="375" alt="Surge Relay Remote Management" src="https://github.com/user-attachments/assets/83509a1d-e505-4c28-b1c1-cdf6e9d80870" />
</p>

### 2. 稳定的模块分发地址

Surge Relay 会将处理后的 Surge `.sgmodule` 文件发布到私有 GitHub 仓库，并通过 Cloudflare 提供稳定地址；也可以保存到本地 iCloud Drive 目录。所有 iPhone、iPad、Apple TV 和 Mac 上的 Surge App 只需要订阅这些固定 URL。

即使上游模块地址发生变化，你也只需要在 Surge Relay 中修改一次。设备端的订阅地址保持不变，不需要重新安装模块，也不需要逐台修改配置。

<p align="center">
  <img width="375" alt="image" src="https://github.com/user-attachments/assets/66c7c16a-f82c-4a55-b640-c5fcefb3cf99" />
  <img width="375" alt="image" src="https://github.com/user-attachments/assets/6bb34ca7-c4c3-43b3-9b48-284eeeda8f65" />
</p>


### 3. 本地转换与自动发布

Surge Relay 运行在你的 Mac 上，负责拉取上游模块、调用 Script-Hub 的本地转换逻辑、应用自定义规则，并生成最终可用的 Surge 模块。

生成后的模块可以自动发布到私有 GitHub 仓库并搭配 Cloudflare，或保存到 iCloud Drive (推荐)。为避免公开仓库被批量滥用，Surge Relay 不允许将公开仓库用作同步目标。Mac 只负责构建和发布，用户设备读取的是已经发布好的稳定文件。因此，即使 Mac 关机或暂时无法连接，已经发布的模块仍然可以正常使用。

#### Github 和 Cloudflare Worker 配置教程

- [从零配置 GitHub 私有仓库与 Cloudflare Worker](docs/GitHub-Cloudflare-Guide.md) — 面向新手的图文教程，包含 Token 权限、Worker 配置、验证方法和常见错误。
- 你可以使用 AI 工具，例如 Claude Code 或 Codex 进行一键部署。如果你觉得操作过于繁琐，建议直接使用 iCloud 同步模式，无需此步骤 (最推荐🌟)。

### 4. 可视化编辑与规则控制

Surge Relay 提供图形化界面，用于查看和编辑模块内容。

你可以集中管理模块地址、删除不需要的模块、屏蔽指定 MITM hostname、禁用部分 Script 或 Rewrite 规则，并对模块参数进行可视化调整。

相比手动编辑 `.sgmodule` 文件，Surge Relay 更适合长期维护大量模块。

<p align="center">
  <img width="375" alt="Surge Relay Module Editor" src="https://github.com/user-attachments/assets/236a7812-5c2e-48d2-8f49-cb12464cdf12" />
  <img width="375" alt="Surge Relay Remote Management" src="https://github.com/user-attachments/assets/3d56e0c6-690c-4d09-9362-7bdab7c2b2fe" />
</p>

### 5. Web 端远程管理

除了 macOS 原生 App，Surge Relay 也支持 Web 端远程管理。你可以通过浏览器查看模块状态、检查同步结果、调试转换问题，或远程修改模块配置。

配合 Surge Ponte 功能，即使不在 Mac 旁边，也可以从你的任意一台设备访问 Surge Relay，完成状态查看、调试和编辑等操作。

多台 Mac 还可以在“设置 → Surge Ponte”中分别设置设备角色。服务器 Mac 继续使用原有的 iCloud 或 GitHub 流程转换、同步和发布；客户端 Mac 作为远程管理入口，通过 Ponte 连接服务器，并使用与服务器相同的原生界面进行管理（不再内嵌网页）。客户端选择“客户端模式”后，自行输入服务器的 Ponte 地址（例如 `johnsmac.sgponte`）并验证连接即可。设备角色与 Ponte 地址只保存在当前 Mac，不会随 iCloud 配置同步到其他设备。客户端模式下无法再次开启本机 Web 服务，请前往服务器端进行 Web 管理。

<p align="center">
  <img width="62%" alt="image" src="https://github.com/user-attachments/assets/294ea6e5-4791-48bb-9e78-b0a2527eee32" />
  <img width="24%" alt="image" src="https://github.com/user-attachments/assets/b0e782bb-984d-43ec-9af3-6820f4308b21" />
</p>

### 6. 多设备自动同步

所有设备只需要订阅 Surge Relay 发布后的固定模块地址。后续模块更新、上游地址修复、MITM 调整、规则禁用等操作，都可以在 Surge Relay 中统一完成。

当新的模块文件发布后，设备端会随着 Surge 的模块更新机制自动同步，避免重复配置和手动迁移。

<p align="center">
  <img width="62%" alt="Surge Relay Landscape Preview" src="https://github.com/user-attachments/assets/7dcee1b6-e2cf-4cee-9a20-293b075bf67b" />
  <img width="24%" alt="Surge Relay Portrait Preview" src="https://github.com/user-attachments/assets/b7e8040a-7dfa-4dd0-bbba-89446e933ea1" />
</p>

## 如果遇到“App 已损坏，无法打开，你应将其移到废纸篓”
此提示并不代表 App 真的损坏。只是因为没有经过 Apple 付费公证，macOS 自动加上了“隔离”标记。

请按照以下提示操作：

1.打开“终端”(“访达”>“应用程序”>“实用工具”>“终端”)。

2.拷贝并粘贴至终端如下命令后按 Return (回车) 键：

```bash
  sudo xattr -rd com.apple.quarantine /Applications/Surge\ Relay.app
```

3.输入 Mac 的开机密码 (输入时不会显示任何字符) 后按 Return (回车) 键。

4.重新打开 Surge Relay，即可正常使用。

## 声明

本项目展示页面中的模块、模块名称、作者名称及相关来源，仅用于说明 Surge Relay 的模块管理、转换、汇总和分发能力，不代表本项目对任何模块内容、使用方式、适用场景或安全性的推荐、背书、指导或保证。

示例中展示的模块来源可能包括但不限于：Surge Relay、@小白脸、@xream、@keywos、@ckyb、Ethan、[RuCu6](https://github.com/RuCu6)、[Maasea](https://github.com/Maasea)、[fmz200](https://github.com/fmz200)、[kelv1n1n](https://github.com/kelv1n1n)、[可莉🅥](https://github.com/luestr/ProxyResource/blob/main/README.md)、[zmqcherish](https://github.com/zmqcherish)、[VirgilClyne](https://github.com/VirgilClyne)、[zirawell](https://github.com/zirawell)、wish、奶思等。

所有模块的版权、署名、许可协议和使用限制均归原作者或原项目所有。Surge Relay 仅提供本地化的模块管理、转换、编辑和发布工具能力。用户在使用、转换、编辑、分发或订阅相关模块前，应自行确认对应模块的来源、许可、用途、风险和合规性。

## 反馈

如果你有任何问题，请在 Github 提交 Issue。
