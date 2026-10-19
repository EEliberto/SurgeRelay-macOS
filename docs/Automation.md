# 自动化访问

Surge Relay 261019 提供本机 REST API 和 MCP 接入脚本，可供外部 Agent 或自动化工具读取模块、机场订阅和诊断信息，预览修改并执行刷新、发布。

## 开启访问

1. 在作为服务器的 Mac 上，打开 Surge Relay 的“设置”>“Web 管理”。
2. 开启“允许本机 Agent 访问”。此操作也会开启 Web 管理。
3. 点按“拷贝访问令牌”，将令牌填入自动化工具的配置。
4. 根据需要开启“允许编辑”“允许刷新”或“允许发布”。默认只允许读取。

API 地址为 `http://127.0.0.1:8787/api/v1`。如果更改过 Web 管理端口，请使用设置中显示的地址。App 需要保持运行；关闭主窗口后可以继续在菜单栏运行。自动化 API 仅接受本机连接，不通过 Surge Ponte 开放。

“允许编辑”用于应用预览中的修改。“允许刷新”用于重新下载和转换来源。模块设置变更会触发刷新，因此还需要刷新权限。若已开启自动同步，或使用 iCloud 输出（包括单独输出模块），修改和模块刷新还需要发布权限。机场刷新会沿用现有行为，更新订阅缓存与直连规则；写入节点策略文件需执行 `writeAirports`，并具有发布权限。

重置令牌后，旧令牌立即失效，尚未应用的计划也会清除。关闭 Web 管理后，自动化 API 随之停止。

## 通过 MCP 接入

下载仓库中的 [`surge-relay-mcp.py`](../tools/surge-relay-mcp.py)，保存到本机。脚本需要 Python 3.9 或更高版本，无需安装其他 Python 包。

在支持 MCP stdio 的工具中添加服务器，使用以下配置；将脚本路径和令牌替换为实际值：

```json
{
  "mcpServers": {
    "surge-relay": {
      "command": "python3",
      "args": ["/absolute/path/surge-relay-mcp.py"],
      "env": {
        "SURGE_RELAY_TOKEN": "从 App 拷贝的访问令牌",
        "SURGE_RELAY_PORT": "8787"
      }
    }
  }
}
```

不同工具的配置文件位置和外层格式可能不同。服务器的启动命令、参数和环境变量保持一致即可。

可使用的工具：

| 工具 | 用途 |
| --- | --- |
| `relay_status` | 查看权限、运行状态和失败信息 |
| `relay_list_modules` / `relay_list_airports` | 列出模块或机场订阅 |
| `relay_read_module` | 读取模块设置，或通过 `content: true` 读取可编辑正文 |
| `relay_read_airport` | 读取机场设置，或通过 `nodes: true` 查看节点处理结果 |
| `relay_read_configuration` | 查看机场配置预览及策略文件是否存在 |
| `relay_search` | 搜索模块正文，返回来源、配置段和行号 |
| `relay_plan` | 生成修改预览，不写入配置 |
| `relay_apply` | 应用已确认的修改计划 |
| `relay_start_job` / `relay_job` | 启动任务并查询完成或失败结果 |

例如，可以要求 Agent：“找出包含 example.com 的配置，列出来源模块和行号”，或“将这个机场的保留关键词改为香港，先给我看修改内容”。

## 直接调用 REST API

所有请求均需携带 `Authorization: Bearer <令牌>`。以下示例假定令牌已保存到环境变量 `SURGE_RELAY_TOKEN`：

```sh
curl --noproxy '*' \
  -H "Authorization: Bearer $SURGE_RELAY_TOKEN" \
  http://127.0.0.1:8787/api/v1/capabilities
```

| 方法 | 路径（相对于 `/api/v1`） | 返回内容或用途 |
| --- | --- | --- |
| GET | `/capabilities` | API 版本、权限和支持的操作 |
| GET | `/modules` | 模块列表与刷新状态 |
| GET | `/modules/{id}` | 模块设置与 `revision` |
| GET | `/modules/{id}/content` | 正文与 `revision` |
| GET | `/airports` | 机场列表与缓存状态 |
| GET | `/airports/{id}` | 机场设置与 `revision` |
| GET | `/airports/{id}/nodes` | 原始名称、处理后名称和过滤结果 |
| GET | `/search?q=example.com&limit=100` | 来源模块、配置段、行号与匹配内容 |
| GET | `/configuration` | 机场配置预览、目标配置与策略文件是否存在 |
| GET | `/diagnostics` | 当前运行状态、失败模块和发布检查结果 |
| POST | `/plans` | 创建修改预览 |
| POST | `/plans/{planID}/apply` | 应用修改 |
| POST | `/jobs` | 启动刷新或发布任务 |
| GET | `/jobs` 或 `/jobs/{id}` | 查询任务结果 |

列表中的来源 URL 不返回用户名、密码或查询参数。正文、配置预览和设置接口用于完整编辑，可能包含用户配置的私有内容，请仅向需要处理这些内容的工具授权。API 不提供 GitHub Token 或自动化令牌的读取接口。

### 修改设置

先读取目标的设置和 `revision`，再创建计划：

```json
{
  "kind": "airport.settings",
  "id": "机场 UUID",
  "baseRevision": "读取时返回的 revision",
  "changes": {
    "nodeProcessing": {
      "includeKeywords": ["香港"]
    }
  }
}
```

支持的计划类型：

- `airport.settings`：名称、正则筛选、节点名称模板、名称优化和节点处理选项。
- `module.settings`：名称、来源格式、刷新间隔和 Script Hub 选项。`refreshIntervalMinutes` 为 `null` 时表示“自动”，`0` 表示仅手动刷新。
- `module.content`：使用 `content` 字段提交完整正文。`baseRevision` 必须来自正文接口。

`changes` 只更新明确提供的字段，嵌套对象中未提供的选项会保留；未知字段会被拒绝。机场或模块的来源地址、账户凭据不通过此接口修改。

计划返回 `before`、`after`、`planID` 和过期时间。确认差异后，对 `/plans/{planID}/apply` 发送 POST。计划有效期为 10 分钟，只能成功应用一次；如果内容已被 App 或其他工具修改，会返回 `409`，需要重新读取并预览。修改保存后，输出同步沿用 App 的现有设置。

### 刷新与发布

向 `/jobs` 提交以下请求之一：

```json
{"action":"refreshModules","id":"模块 UUID"}
```

```json
{"action":"refreshAirport","id":"机场 UUID"}
```

```json
{"action":"publish"}
```

```json
{"action":"writeAirports"}
```

`refreshModules` 不传 `id` 时刷新所有符合条件的模块。`publish` 发布到已配置的 GitHub 与 Cloudflare；iCloud 模式在内容更新时自动导出，无需单独发布。`writeAirports` 向已启用的 Surge 配置写入机场策略文件和配置引用。

返回 `202` 表示任务已接收，不表示已完成。使用返回的任务 `id` 查询，直到 `state` 为 `succeeded` 或 `failed`。失败原因位于 `message`。模块刷新任务完成表示来源处理结束，自动发布仍按 App 设置执行；需要确认远程发布结果时，请单独执行 `publish` 并查询其结果。任务记录保留最近 100 条，退出 App 后清除。其他任务正在执行时返回 `409`，请等待其完成。

### 错误处理

- `400`：参数、字段类型或配置内容无效。
- `403`：访问未开启、令牌无效、不是本机请求，或缺少对应权限。
- `404`：目标、任务或计划不存在；计划也可能已过期或已应用。
- `409`：内容已变化、App 正忙，或来源暂不允许再次刷新。

接口不接受浏览器跨域请求。MCP 脚本使用本机直连，不经过系统 HTTP 代理，也不跟随重定向。
