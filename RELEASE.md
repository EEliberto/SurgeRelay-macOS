# Surge Relay macOS 更新发布流程

> 发布前必须完整阅读。目标是发布 macOS 更新；除非用户明确要求，不得上传 iOS 源码或 iOS 工程配置。

## 不可违反

- 从 `origin/main` 创建干净的临时 worktree，只同步本次 macOS 改动。
- 每次发布使用新的 `CURRENT_PROJECT_VERSION` 和新的 DMG 文件名。
- App 必须使用 **ad-hoc 签名**；不得传入 `DEVELOPMENT_TEAM` 或 `Apple Development`。
- DMG 必须使用 **UDZO**，且不得再用 `codesign` 签 DMG。
- Sparkle 必须指定钥匙串账号 `com.allenmiao.SurgeRelay`，不能依赖默认 `ed25519`。
- App 内 `SUPublicEDKey` 必须保持：
  `FEcOaL+hwqoGMoia0HFa+ejmGKDUH/NNyyUDf9kEOBQ=`
- 新版本验证完成前，不得删除旧 Release 资产。即使新版本上线，也应保留旧资产，避免客户端缓存旧 appcast 后下载到 404。
- 不要直接把本地 `SurgeRelayIOS/`、`SurgeRelayIOSTests/` 或含 iOS 目标的本地 `project.yml` 同步到 macOS 发布分支。

## 1. 准备隔离发布目录

```sh
git fetch origin main
git worktree add --detach /tmp/SurgeRelayRelease origin/main
```

仅复制本次 macOS 文件到 worktree。若 `project.yml` 引用本地图标，可只将 `Surge Relay.icon` 复制到临时 worktree 用于构建，不要因此上传图标或 iOS 文件。

更新 `project.yml` 中 `CURRENT_PROJECT_VERSION`，然后在临时 worktree 执行：

```sh
xcodegen generate
```

生成后确认 `project.pbxproj` 不包含 `SurgeRelayIOS`、`iphoneos` 或 iOS target。

## 2. 构建 ad-hoc Release

```sh
xcodebuild \
  -project "Surge Relay.xcodeproj" \
  -scheme "Surge Relay" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/SurgeRelayBuild \
  clean build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO
```

检查版本和签名：

```sh
APP="/tmp/SurgeRelayBuild/Build/Products/Release/Surge Relay.app"
/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist"
codesign -dv --verbose=2 "$APP" 2>&1
```

输出必须包含 `Signature=adhoc`、`TeamIdentifier=not set`。

## 3. 创建 UDZO DMG

```sh
STAGE=/tmp/SurgeRelayDMG
DMG="/tmp/Surge-Relay-<版本>-build-<构建号>.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Surge Relay" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
```

不要对 DMG 运行 `codesign`。

## 4. 使用正确 Sparkle 私钥签名

```sh
SIGN="/path/to/Sparkle/bin/sign_update"
"$SIGN" --account com.allenmiao.SurgeRelay "$DMG"
```

把输出的 `sparkle:edSignature` 和 `length` 原样写入 `appcast.xml`。必须再验证：

```sh
"$SIGN" --account com.allenmiao.SurgeRelay --verify "$DMG" "<edSignature>"
```

## 5. 更新 appcast 并发布

- `sparkle:version` 改为新构建号。
- enclosure URL 使用新的 DMG 文件名。
- `length` 必须等于 `stat -f%z "$DMG"`。
- `sparkle:edSignature` 必须来自上一步指定账号的输出。
- 先提交并推送 `main`，再上传新 DMG 到对应 GitHub Release。
- 不删除旧 DMG。

## 6. 发布后端到端验证

```sh
curl -sL "<新 DMG URL>" -o /tmp/SurgeRelayPublished.dmg
test "$(stat -f%z /tmp/SurgeRelayPublished.dmg)" = "<appcast length>"
"$SIGN" --account com.allenmiao.SurgeRelay \
  --verify /tmp/SurgeRelayPublished.dmg "<appcast edSignature>"
```

再挂载线上 DMG，确认内部 App：

```sh
hdiutil attach /tmp/SurgeRelayPublished.dmg -readonly -nobrowse -mountpoint /tmp/SurgeRelayMount
codesign -dv "/tmp/SurgeRelayMount/Surge Relay.app" 2>&1
/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' \
  "/tmp/SurgeRelayMount/Surge Relay.app/Contents/Info.plist"
hdiutil detach /tmp/SurgeRelayMount
```

最后确认：

- raw appcast 已显示新构建号、URL、长度和签名。
- DMG URL 返回 HTTP 200，完整下载大小正确。
- 线上 DMG 的 Sparkle 签名验证通过。
- DMG 内 App 是 ad-hoc 签名且构建号正确。
- 旧 Release 资产仍可下载。

只有以上检查全部通过，才可以通知用户更新已上线。
