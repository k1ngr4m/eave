# Eave

把音乐、系统状态和常用工具放到 Mac 的刘海与菜单栏。

Eave 是一个原生 macOS 桌面工具，支持刘海屏、普通屏幕和多显示器。你可以在屏幕顶部控制音乐、查看歌词与硬件状态、暂存文件，或打开计时器、笔记和终端；菜单栏面板则集中提供电池、网络、蓝牙与音量控制。

[下载最新版](https://github.com/k1ngr4m/eave/releases/latest) · [更新日志](CHANGELOG.md) · [反馈问题](https://github.com/k1ngr4m/eave/issues) · [许可证](LICENSE)

> 本文介绍当前仓库的实现，部分改动可能尚未发布。已发布版本的功能与安装说明以 [Releases](https://github.com/k1ngr4m/eave/releases) 为准。

## 主要功能

| 类别           | 功能                                                                                                                   |
| -------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 刘海与外观     | 悬停展开、快捷键切换、滚动手势、保持展开、多屏显示、自定义动画，以及仅保留媒体与系统 HUD 的简约模式。                  |
| 音乐与歌词     | 播放控制、专辑封面、实时音频频谱、同步歌词、歌词时间调整、固定歌词字号与上下文行数、悬浮播放器和锁屏媒体面板。         |
| 系统控制       | 音量、亮度、键盘背光 HUD；单应用音量与静音；BetterDisplay、Lunar 集成及受支持外接屏的直接 DDC 音量控制。               |
| 菜单栏状态     | 三合一状态图标；电池、网络、蓝牙和音量面板；可排序、可开关的面板模块。                                                 |
| 实时提示       | 充电、低电量、充满电、下载、录屏、专注模式、大小写锁定、摄像头／麦克风使用和蓝牙连接等状态。                           |
| 硬件监控       | CPU、GPU、内存、磁盘、网络和传感器读数，详情面板、图表及折叠状态小组件；各模块可单独配置。                             |
| 桌面信号       | 按键拖动唤出信号轮盘、动画与音效、自定义轮盘布局、大小和持续时间，以及快捷键暂停。 |
| 效率工具       | 自定义计时器与预设、系统计时器镜像、日历、提醒事项、保持唤醒、笔记、Apple Notes 同步和下拉终端。 |
| 文件暂存与分享 | Shelf 拖放暂存、预览、拖出操作、Quick Share、AirDrop，以及通过 LocalSend 协议向兼容设备发送文件。                      |
| AI 用量        | 查看 Claude Code、Codex、Cursor、Antigravity 和 New API 的用量或额度；可显示的数据由各来源决定。                       |
| 锁屏与其他工具 | 锁屏天气、空气质量、日历、提醒、电池与专注组件；摄像头镜子、A 股自选与行情、自定义 Lottie 动画。                       |

媒体控制由系统“正在播放”和各播放器适配器提供，播放控制、收藏、封面与歌词能力因播放器而异。歌词也受在线歌词源的曲目覆盖影响。

AI 用量面板会结合本地日志与服务端额度接口：Claude Code、Codex 可读取本地使用记录，Cursor 主要提供额度信息，Antigravity 优先读取本地语言服务，New API 支持多个账户。不同服务的数据项与统计口径并不相同。

## 安装与更新

### 安装发布版

1. 打开 [最新 Release](https://github.com/k1ngr4m/eave/releases/latest)，Intel Mac 选择 `Eave-<版本>-Intel.dmg`，M 系列 Mac 选择 `Eave-<版本>-AppleSilicon.dmg`。最低系统要求为 macOS 14.6；不带架构后缀的 ZIP 是供自动更新使用的通用包，也可手动安装。
2. 使用 DMG 时打开磁盘映像，将 `Eave.app` 拖入“应用程序”；使用 ZIP 时先解压，再将 `Eave.app` 移入“应用程序”。
3. 从“应用程序”启动 Eave，完成首次设置，按需要启用功能并授予权限。

[0.1.1 发布说明](https://github.com/k1ngr4m/eave/releases/tag/v0.1.1)提供 DMG 和 ZIP 两种安装包。该版本采用本地 ad-hoc 签名，**未经 Apple 公证**。如果首次启动被系统拦截，在尝试打开后进入“系统设置 → 隐私与安全”，找到 Eave 的提示并选择“仍要打开”。

`appcast.xml` 是应用更新源，无需手动安装。更新 ZIP 使用 Eave 的 Ed25519 密钥签名；更新签名与 Apple 公证是两件不同的事。

### 更新应用

正式发布版使用 Sparkle 检查更新，可在应用设置中检查新版本，也可从 Releases 下载后替换“应用程序”中的旧版本。

标记为 `dev` 的开发构建不连接正式更新源。Xcode 的 `Debug`／`Release` 编译配置与 Eave 的 `dev`／`release` 分发渠道相互独立，直接选择 Release 编译不会自动开启正式版更新。

## 快速使用

1. **展开面板**：将指针移到屏幕顶部的刘海／灵动岛区域，或按 `⌘⇧I`。悬停、手势、展开行为与显示屏可在设置中调整。
2. **打开设置**：通过菜单栏中的 Eave 入口进入设置，选择显示模式、音乐来源和常用模块。
3. **启用需要的工具**：监控、AI 用量、终端和笔记可在对应设置中启用；首次设置选择 Developer 配置时会自动开启监控和终端。简约模式会隐藏额外工具，仅保留媒体与系统 HUD。
4. **播放音乐**：先在播放器中开始播放，再查看媒体面板。若需要特定播放器的控制或收藏能力，在设置中选择相应来源并完成授权。
5. **暂存文件**：将文件拖到 Shelf，在面板中预览、拖出或分享。使用 LocalSend 协议发送时，接收设备需要运行兼容接收端并可通过局域网访问；Mac 本机无需另装 LocalSend 才能使用内建发送功能。

在“设置 → 实用工具 → 桌面信号”中启用新模块并允许辅助功能访问。默认按住 `⌥ Option` 拖动，松开发送信号；在轮盘中心松开、右键或 `Esc` 取消，`⌃⌥P` 暂停／恢复。功能默认关闭。在同页开启“表情”后，默认按住 `⌃ Control` 拖动发送表情，也可配置单击表情。内置 44 个动画表情，可导入最多 24 张 PNG、JPEG、GIF 或 WebP 图片（仅保存在本机）；表情共用音量、静音及暂停。房间联机尚未接入。信号层独立于刘海的录屏隐藏设置；屏幕共享时应共享整个显示器。

笔记编辑器的清单按钮可插入任务，眼睛按钮切换 Markdown 预览；预览中可直接勾选任务。编辑时按 `Shift + Return` 续写项目符号、编号或任务列表，在空列表项上按同一快捷键结束列表。标题、颜色、图片、搜索及 Apple Notes 同步保持原有方式；同步保存 Markdown 原文（含 `- [ ]` / `- [x]`），不转换为 Apple Notes 原生清单。

### 默认快捷键

快捷键可在设置中修改；需要开启全局快捷键及对应功能。`⌘` 表示 Command，`⇧` 表示 Shift，`⌃` 表示 Control。

| 操作                  | 默认快捷键                |
| --------------------- | ------------------------- |
| 展开／收起刘海面板    | `⌘⇧I`                 |
| 媒体速览              | `⌘⇧H`                 |
| 下拉终端              | Control + 反引号（&#96;） |
| 启动 5 分钟演示计时器 | `⌘⇧T`                 |
| 切换保持唤醒          | `⌘⇧K`                 |
| 降低／提高键盘背光    | `⌘F1`／`⌘F2`        |
| 打开监控              | 默认未绑定，可自行设置。  |

## 权限与数据

### 按功能授权

无需一次性开放全部权限。使用相关功能时，根据应用提示前往“系统设置 → 隐私与安全”授权；系统要求重新打开应用时，退出并重新启动 Eave。

| 权限                   | 用途                                                                                                                         |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| 辅助功能               | 系统硬件按键处理、HUD 控制及相关系统交互。                                                                                   |
| 系统音频录制／音频采集 | 实时音乐频谱与单应用音量控制。系统中的权限名称随 macOS 版本而异。                                                            |
| 摄像头                 | 镜子模式。                                                                                                                   |
| 日历与提醒事项         | 展示日历事件、提醒及相关组件。                                                                                               |
| 自动化                 | 通过 AppleScript 控制 Spotify、Apple Music 或与 Apple Notes 同步。                                                           |
| 媒体与 Apple Music     | 获取 Apple Music 动态封面等相关内容。                                                                                        |
| 定位                   | 锁屏天气，以及 Wi-Fi 网络名称与详情。                                                                                        |
| 蓝牙                   | 展示和连接已配对设备，读取可用电量信息。                                                                                     |
| 文件与文件夹           | Shelf 需要同时获得 Documents 和 Downloads 的访问权限，或获得完全磁盘访问权限；相关功能还会读取下载目录、保存应用数据。 |
| 完全磁盘访问权限       | Shelf 的全局文件访问及专注模式的自定义名称、颜色、图标等功能；基本专注状态检测不要求此权限。                                 |

### 数据如何处理

- **音频**：频谱和单应用音量处理链实时处理音频，不录制或保存声音。
- **账户与密钥**：New API 密钥保存在 macOS Keychain。
- **联网数据**：歌词、天气、行情、部分封面、AI 额度和更新检查会访问各自的数据源。AI 用量也可能读取相应工具的本地日志或凭据。

## 从源码构建

### 准备开发环境

- macOS 与完整安装的 **Xcode 26 或更新版本**，包含 macOS 26 SDK；当前源码使用了该 SDK 的界面 API。应用的最低运行系统仍为 macOS 14.6。
- Git、Git LFS、Python 3，以及 Homebrew。
- 手机电量 Helper 的构建工具：`autoconf`、`automake`、`libtool`、`pkg-config`。

先在 Xcode 中完成首次启动配置，并确认 `xcode-select -p` 指向所用 Xcode 的 Developer 目录。

```bash
brew install autoconf automake libtool pkg-config git-lfs

git clone https://github.com/k1ngr4m/eave.git
cd eave
git lfs install --local
git lfs pull
```

仓库中的部分动画和视频使用 Git LFS；拉取后应取得实际资源文件。Swift Package Manager 会在构建时解析项目依赖。

### 使用 Xcode

```bash
open DynamicIsland.xcodeproj
```

选择 **DynamicIsland** scheme 和 **My Mac**，使用 Debug 配置运行。若使用 Apple Development 签名，请在 Signing & Capabilities 中选择自己的 Team；工程中的已有 Team 标识不适用于其他开发者。

### 使用命令行

以下命令使用本地 ad-hoc 签名构建 Debug 应用，无需开发者分发证书：

```bash
xcodebuild build \
  -project DynamicIsland.xcodeproj \
  -scheme DynamicIsland \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES

open build/DerivedData/Build/Products/Debug/Eave.app
```

如果 Xcode 提示缺少 Metal 工具链，可安装对应组件后重新构建：

```bash
xcodebuild -downloadComponent MetalToolchain
```

### 构建时会发生什么

- `EaveStatus` 和 `EaveNetworkStats` 是仓库内的本地 Swift Package，无需另外克隆 Status Trio 或 Stats，也无需相邻项目目录。
- Xcode 构建阶段自动编译并嵌入 `EaveMobileBatteryHelper` 及其动态库。首次构建会按 [依赖清单](Support/mobile-battery-dependencies.json)下载固定提交的 OpenSSL、libimobiledevice 等源码，因此需要联网且耗时较长。
- Helper 的依赖构建缓存在 `.build/mobile-battery/`；后续构建会在条件匹配时复用。生成的应用携带运行依赖，不依赖用户机器上的 Homebrew。
- 应用版本来自 `VERSION`，每次构建自动写入分发渠道和本机构建号。

### 菜单栏新增选项

在 Eave 的菜单栏状态设置中，可以选择用输入法作为图标中心，并启用输入法切换面板；菜单栏和 Dock 使用同一份状态。电池满格阈值只决定圆环何时画满，百分比仍显示真实电量，也不会修改系统充电限制。网络摘要可显示内网 IP，网络面板提供互联网共享设置入口。DDC 音量控制同步了上游的显示器匹配和读取兼容性修复。

低电量模式控制默认关闭。启用后，按提示在 macOS 系统设置中批准 Eave 辅助程序，再从电池面板切换。构建阶段会嵌入 `EavePowerHelper`；此功能需要有效的 Apple 签名，ad-hoc 构建会显示不可用。辅助程序仅接受匹配 Eave Bundle ID 和 Team ID 的客户端；使用自己的开发团队构建时，还需同步修改 `Packages/EaveStatus/Sources/PowerHelperProtocol/` 中的客户端签名要求。辅助程序按需启动，空闲时退出。

## 项目结构

```text
eave/
├── DynamicIsland/             # 主应用：SwiftUI / AppKit 界面、管理器、媒体和音频
├── DynamicIsland.xcodeproj/   # Xcode 工程与共享 scheme
├── DynamicIslandTests/        # 应用单元测试
├── DynamicIslandUITests/      # 界面测试
├── Packages/
│   ├── EaveStatus/            # 菜单栏状态与控制面板
│   └── EaveNetworkStats/      # CPU、GPU、内存、磁盘、网络与传感器监控
├── Support/                  # 手机电量 Helper、依赖清单及第三方声明
├── scripts/                  # 构建、校验、版本和发布脚本
├── tests/                    # Python / Swift 回归检查
├── .github/workflows/        # 持续集成工作流
├── VERSION                   # Eave 应用版本
├── CHANGELOG.md              # Eave 与上游历史更新记录
└── README.md
```

根目录没有 `Package.swift`，整个应用通过 Xcode 工程构建；`swift test` 用于两个本地包。

## 测试

以下命令均从仓库根目录运行。可按改动范围选择相关检查。

### Python 回归检查

使用 Python 3 标准库，无需额外安装 Python 测试依赖：

```bash
python3 tests/test_eave_identity.py
python3 tests/test_eave_version.py
python3 tests/test_eave_updates.py
python3 tests/test_settings_localization.py
python3 tests/test_privacy_configuration.py
python3 tests/test_timer_lifecycle.py
```

这些检查分别覆盖应用标识、版本、更新流程、本地化、权限配置和计时器生命周期。计时器检查还会调用 `swiftc` 编译回归程序，需要已配置的 Swift 工具链。

### Swift Package 与 Helper

```bash
swift test --package-path Packages/EaveStatus
swift test --package-path Packages/EaveNetworkStats

bash scripts/test-mobile-battery-helper.sh
bash scripts/test-mobile-battery-rpaths.sh
bash scripts/test-mobile-battery-clang-version.sh
```

### 应用与交互测试

在 Xcode 中选择 DynamicIsland scheme，使用 Product → Test 运行应用测试。应用单元测试 target 要求 macOS 15 或更新版本；界面测试需要可交互的 macOS 桌面及相关权限。

监控的实时／界面检查见 [监控测试脚本](tests/test_monitoring.py) 和 [监控模块说明](Packages/EaveNetworkStats/UPSTREAM.md)。该脚本默认使用 `.build/stats-monitoring/Build/Products/Debug`；若使用上面的构建命令，需将 `EAVE_MONITORING_PRODUCTS` 指向 `build/DerivedData/Build/Products/Debug` 的绝对路径。

`test_eave_updates.py` 的可选 `--swift` 检查从 Xcode 默认 DerivedData 目录寻找 Sparkle，不会自动使用上面自定义的 `build/DerivedData` 路径。

[当前 CI](.github/workflows/ci.yml)执行回归检查、Helper 检查、EaveStatus 测试、一个网络模块定向测试与应用编译，并检查 Sparkle 生命周期；它不运行完整 XCUITest，也不自动发布正式版。

## 版本与发布

### 版本、渠道与应用标识

| 项目             | 规则                                                                                                             |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- |
| 应用版本         | 根目录[VERSION](VERSION)，使用 `major.minor.patch` 格式。                                                       |
| 本机构建号       | 每次构建递增，`dev` 和 `release` 分别计数，默认保存在 `~/Library/Application Support/Eave/BuildNumbers/`。 |
| Debug 应用标识   | `com.eave.app.dev`。                                                                                           |
| Release 应用标识 | `com.eave.app`。                                                                                               |
| 开发渠道         | 工程中的 Debug 和 Release 配置默认均为`EAVE_CHANNEL=dev`。                                                     |
| 正式渠道         | 发布归档显式设置`EAVE_CHANNEL=release`，启用正式更新源。                                                       |

### 维护者发布流程

[发布脚本](scripts/eave_release.py)分为 `prepare` 和 `publish` 两步。它面向维护者，发布目标固定为 `k1ngr4m/eave`，不是普通开发构建的打包快捷方式。

准备发布前需要：

1. 将新版本写入 `VERSION`，更新发行说明并提交源代码，确保工作区干净；新版本必须高于已发布版本，且不存在同名 tag 或 Release。
2. 准备已登录的 GitHub CLI（`gh`）；准备阶段需要读取仓库，发布阶段需要写入 Release。
3. 准备 Sparkle 的 `generate_keys`、`sign_update` 工具，并通过 `--sparkle-bin` 或 `EAVE_SPARKLE_BIN` 指定其所在目录。
4. 确保钥匙串中 `com.eave.app` 对应的 Sparkle 私钥与应用 `SUPublicEDKey` 匹配。
5. 如需 Apple 公证，另行准备 Developer ID Application 证书、Team ID 和 `notarytool` 钥匙串配置。

以下示例中的 `0.1.2` 仅表示待发布的新版本，工具目录和发行说明路径需替换为实际值。

准备 ad-hoc 签名版本（不进行 Apple 公证）：

```bash
python3 scripts/eave_release.py prepare 0.1.2 \
  --signing local \
  --sparkle-bin /path/to/Sparkle/bin
```

如需公证，改用以下准备命令：

```bash
python3 scripts/eave_release.py prepare 0.1.2 \
  --signing notarized \
  --sparkle-bin /path/to/Sparkle/bin \
  --identity 'Developer ID Application: YOUR NAME (TEAMID1234)' \
  --team TEAMID1234 \
  --notary-profile EaveNotary
```

准备产物位于 `build/release-<版本>/`，包括通用 `export/Eave.app`、供自动更新使用的 `Eave-<版本>.zip`、独立的 `Eave-<版本>-Intel.dmg` 和 `Eave-<版本>-AppleSilicon.dmg`、`appcast.xml` 和用于校验的 `release.json`。独立安装包从同一归档提取对应架构，检查嵌套代码签名，并提供拖入“应用程序”的 DMG 安装界面。归档位于 `build/Eave-<版本>.xcarchive`。

检查产物并确保该源代码提交已经推送到远端后，使用非空发行说明文件发布：

```bash
python3 scripts/eave_release.py publish 0.1.2 \
  --notes /path/to/release-notes.md
```

`publish` 会校验产物、创建草稿 Release、下载核对上传结果，再将其转为公开的最新 Release。已存在的版本不会被覆盖。

## 常见问题

### 没有刘海的 Mac 能用吗？

可以。Eave 支持普通屏幕和外接显示器，可在设置中调整显示屏与面板外观。

### 启动后没有看到普通应用窗口或 Dock 图标？

Eave 主要驻留在菜单栏与屏幕顶部，并不依赖普通主窗口。先检查菜单栏入口，或使用 `⌘⇧I` 展开面板；也可以从“应用程序”再次打开 Eave 进入设置。

### 快捷键、HUD 或某个工具不生效？

确认对应功能和全局快捷键已开启，检查绑定是否冲突。HUD 和硬件按键处理需要辅助功能权限；录音、镜子、截图等功能有各自权限。简约模式会隐藏额外工具。

### 音乐在播放，但没有歌词、封面或某些控制？

先检查设置中的音乐来源和播放器授权。不同来源暴露的媒体信息不同；歌词还依赖曲目信息和在线歌词源，并非所有曲目都有同步歌词。实时频谱需要系统音频采集权限。

### 某些设备电量、温度或磁盘数据为空？

硬件和系统不一定提供所有指标。确认模块已开启、蓝牙设备已连接，手机已完成系统要求的配对或信任流程。外接显示器的直接 DDC 音量控制还受处理器架构、显示器数量与协议支持限制。

### 下载提示为什么没有覆盖所有应用？

当前下载检测监测 Downloads 目录，面向 Safari、Firefox、Chrome 及 Chromium 系浏览器；其他应用或自定义下载位置不一定会被识别。

### 开发构建为什么没有正式版更新？

`dev` 渠道有意关闭正式更新检查。仅将 Xcode 配置改成 Release 不会改变渠道；正式渠道由发布归档流程设置。

### 首次构建很慢，或提示缺少 Helper／Metal 依赖？

首次构建会解析 Swift 包并下载、编译 Helper 的固定版本依赖。确认构建工具已安装、网络可访问依赖仓库，且 Xcode 已完成首次配置。Metal 组件缺失时使用上文的下载命令。

### 终端会话会一直保留吗？

收起和重新展开面板时，终端进程会继续运行；这不等同于退出 Eave 或重启系统后的会话恢复。

## 反馈与贡献

通过 [GitHub Issues](https://github.com/k1ngr4m/eave/issues)报告问题或提出建议。反馈时请附上 Eave 版本与渠道、macOS 版本、Mac 芯片、相关外设、复现步骤及预期结果；界面问题可补充截图。

欢迎提交修复、功能改进与本地化 Pull Request。请围绕具体问题保持改动清晰，运行相关测试，并在 PR 中说明行为变化与验证方式。上传日志或截图前，请移除 API Key、Token 和个人内容。

## 许可与致谢

Eave 按 [GNU GPL v3](LICENSE) 许可发布；源文件中的相应声明允许使用 GPL v3 或后续版本。第三方代码和素材保留各自的许可与版权，详见 [NOTICE](NOTICE)、[素材版权声明](COPYRIGHT_ASSETS) 和 [商标声明](TRADEMARKS)。

感谢 Atoll、boring.notch 及以下项目与作者：

| 来源                    | 在 Eave 中的用途与声明                                                                                                                                |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status Trio             | 菜单栏状态模块，Apache License 2.0；见[许可证](Packages/EaveStatus/LICENSE)和[来源说明](Packages/EaveStatus/NOTICE)。                                   |
| Stats                   | 硬件监控读取器、图表、设置与传感器定义，MIT License；见[许可证](Packages/EaveNetworkStats/LICENSE)和[集成说明](Packages/EaveNetworkStats/UPSTREAM.md)。 |
| AppleSiliconDDC         | 外接显示器直接音量控制，见[MIT 许可证](Packages/EaveStatus/Sources/EaveStatus/Resources/AppleSiliconDDC-LICENSE.txt)。                                 |
| libimobiledevice 等依赖 | 手机电量 Helper，见[第三方许可与重链接说明](Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md)。                                                 |
| Eddy Gann / LottieFiles | Fingerprint Scan 动画，来源与许可见[NOTICE](NOTICE)。                                                                                                  |

本项目并非 Apple 官方产品，与 Apple 的 Dynamic Island 产品无隶属关系。
