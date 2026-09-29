<div align="center">
  <br>
  <img src="https://github.com/user-attachments/assets/af9622ea-5c92-46e8-969d-27de2599f41d" width="136" alt="Surge Relay 图标">
  <h1>Surge Relay</h1>
  <h3>管理、转换并发布 Surge 模块</h3>
  <p>在 Mac 上整理模块来源、调整规则，并让每台设备始终使用同一组订阅地址。</p>
  <br>
  <p>
    <a href="https://github.com/EEliberto/SurgeRelay-macOS/releases/latest"><strong>下载 Surge Relay</strong></a>
    &nbsp;&nbsp;·&nbsp;&nbsp;
    <a href="CHANGELOG.md">查看新功能</a>
  </p>
  <p><sub>需要 macOS 26 或更高版本，以及搭载 Apple 芯片的 Mac。</sub></p>
  <br>
</div>

<p align="center">
  <img width="920" alt="Surge Relay 主窗口" src="https://github.com/user-attachments/assets/aee0f362-146d-4bbf-9069-b6fda1f8f886">
</p>

<br>

## 在一个地方管理所有模块

Surge Relay 将模块来源、备用地址和转换规则集中在一个原生 Mac App 中。上游仓库或文件路径发生变化时，只需在 Mac 上更新一次，无需在每台设备上重新安装模块。

<p align="center">
  <img width="375" alt="Surge Relay 模块列表" src="https://github.com/user-attachments/assets/444cbc3d-d4b8-4047-a569-607692123503">
  <img width="375" alt="Surge Relay 模块设置" src="https://github.com/user-attachments/assets/83509a1d-e505-4c28-b1c1-cdf6e9d80870">
</p>

## 保持订阅地址不变

处理后的 Surge `.sgmodule` 文件可以保存到 iCloud 云盘，或发布到私有 GitHub 仓库并通过 Cloudflare 提供访问地址。iPhone、iPad、Apple TV 和 Mac 只需订阅生成后的固定 URL；即使上游地址改变，设备上的订阅也无需重新配置。

<p align="center">
  <img width="375" alt="Surge Relay 发布设置" src="https://github.com/user-attachments/assets/66c7c16a-f82c-4a55-b640-c5fcefb3cf99">
  <img width="375" alt="Surge Relay 同步设置" src="https://github.com/user-attachments/assets/6bb34ca7-c4c3-43b3-9b48-284eeeda8f65">
</p>

## 在 Mac 上完成转换

Surge Relay 使用 [Script-Hub](https://github.com/Script-Hub-Org) 的本地转换能力，获取上游内容、应用转换选项和自定义规则，然后生成可供 Surge 使用的模块。发布完成后，设备读取的是已经生成的文件；Mac 暂时离线不会影响现有订阅。

## 精确调整模块内容

使用图形化编辑器查看模块内容、移除不需要的模块、排除指定的 MITM 主机名，或停用部分 Script 与 Rewrite 规则。常用参数可以直接调整，无需手动编辑 `.sgmodule` 文件。

<p align="center">
  <img width="375" alt="Surge Relay 模块编辑器" src="https://github.com/user-attachments/assets/236a7812-5c2e-48d2-8f49-cb12464cdf12">
  <img width="375" alt="Surge Relay 规则设置" src="https://github.com/user-attachments/assets/3d56e0c6-690c-4d09-9362-7bdab7c2b2fe">
</p>

## 从其他设备继续管理

网页管理界面可用于查看模块状态、检查同步结果和调整配置。配合 Surge Ponte，即使不在 Mac 旁边，也可以从 iPhone 或 iPad 安全地连接到 Surge Relay。

<p align="center">
  <img width="62%" alt="Surge Relay 网页管理界面" src="https://github.com/user-attachments/assets/294ea6e5-4791-48bb-9e78-b0a2527eee32">
  <img width="24%" alt="iPhone 上的 Surge Relay 网页管理界面" src="https://github.com/user-attachments/assets/b0e782bb-984d-43ec-9af3-6820f4308b21">
</p>

## 让所有设备保持同步

模块更新、来源修复和规则调整都可以在 Surge Relay 中统一完成。发布新文件后，各设备会通过 Surge 的模块更新机制获取更改，减少重复安装和手动迁移。

<p align="center">
  <img width="62%" alt="iPad 上的 Surge Relay" src="https://github.com/user-attachments/assets/7dcee1b6-e2cf-4cee-9a20-293b075bf67b">
  <img width="24%" alt="iPhone 上的 Surge Relay" src="https://github.com/user-attachments/assets/b7e8040a-7dfa-4dd0-bbba-89446e933ea1">
</p>

## 开始使用

1. 下载最新的 [Surge Relay DMG](https://github.com/EEliberto/SurgeRelay-macOS/releases/latest)。
2. 打开磁盘映像，并将 Surge Relay 拖移到“应用程序”文件夹。
3. 添加模块来源，并选择 iCloud 云盘或 GitHub 作为存储方式。
4. 完成首次发布后，将生成的固定 URL 添加到 Surge。

使用 GitHub 与 Cloudflare 发布时，请参阅[配置指南](docs/GitHub-Cloudflare-Guide.md)。如果不需要远程分发，选择 iCloud 云盘即可完成多设备同步。

## 如果 Mac 无法打开 Surge Relay

如果系统提示 App 已损坏或无法验证开发者，请打开“终端”App，输入以下命令并按下 Return 键：

```bash
sudo xattr -rd com.apple.quarantine "/Applications/Surge Relay.app"
```

输入 Mac 登录密码后，再次打开 Surge Relay。输入密码时，“终端”不会显示字符。

## 从源码构建

项目使用 SwiftUI 和 Swift 6 构建。使用 Xcode 打开 `Surge Relay.xcodeproj`，然后运行 `Surge Relay` scheme。

<details>
  <summary>模块来源与使用声明</summary>
  <br>
  Surge Relay 仅提供模块管理、转换、编辑和发布功能。README 中出现的模块、作者和来源仅用于展示产品能力，不代表推荐、背书或安全保证。模块的版权、署名、许可协议和使用限制均归原作者或原项目所有。使用、转换、编辑、分发或订阅模块前，请确认相应来源、许可、用途和风险。
  <br><br>
  示例可能包含 Surge Relay、@小白脸、@xream、@keywos、@ckyb、Ethan、<a href="https://github.com/RuCu6">RuCu6</a>、<a href="https://github.com/Maasea">Maasea</a>、<a href="https://github.com/fmz200">fmz200</a>、<a href="https://github.com/kelv1n1n">kelv1n1n</a>、<a href="https://github.com/luestr/ProxyResource/blob/main/README.md">可莉</a>、<a href="https://github.com/zmqcherish">zmqcherish</a>、<a href="https://github.com/VirgilClyne">VirgilClyne</a>、<a href="https://github.com/zirawell">zirawell</a>、wish 和奶思等来源。
</details>

<br>

<div align="center">
  <p><a href="https://github.com/EEliberto/SurgeRelay-macOS/issues">报告问题</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="LICENSE">Apache License 2.0</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="THIRD_PARTY_NOTICES.md">第三方软件声明</a></p>
  <sub>Surge Relay 与 Surge、Apple、GitHub、Cloudflare 及文中提及的模块项目无隶属关系。相关名称和商标归各自所有者所有。</sub>
</div>
