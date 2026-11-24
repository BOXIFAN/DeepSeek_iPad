# iPad-DS 开发文档

> 这是本项目的入口文档。新对话接手时**先读这一份**，再用 `docs/TECH_PLAN.md` 查方案细节、`docs/BUILD_NOTES.md` 查环境坑。
>
> 最后更新：2026-11-24

---

## 1. 项目是什么

用 Swift 原生写一个 iPhone / iPad 通用的 DeepSeek 客户端，替代官方 App 的日常使用。

| 项 | 值 |
|---|---|
| 设备 | iPad Pro 13" (M4)、iPhone 16 Pro，均为 iOS 27 |
| 分发范围 | 只自己用，不上架 |
| 后端 | 没有。客户端直连 `api.deepseek.com` |
| API Key | 存本机 Keychain，不进代码、不进 git |
| 最低部署目标 | iOS 18.0 |
| 当前代码量 | 17 个 Swift 文件，2462 行 |

**不做的事**：多用户、云同步、账号体系、计费、上架审核相关内容。这些在"只自己用"的前提下都没有意义，加进来只会拖慢进度。

---

## 2. 当前状态

一句话：**界面和网络层已经跑通并能编译运行，但还没有用真实 API 完整验证过，消息也不落盘。**

### 功能矩阵

| 能力 | 状态 | 说明 |
|---|---|---|
| 双端自适应布局 | ✅ 完成 | iPad 双栏（`NavigationSplitView`）、iPhone 单列推入 |
| 内容块渲染器 | ✅ 完成 | 思考折叠、搜索合并条、结果卡片、网页提示、引用角标、表格、代码块 |
| Markdown 渲染 | ✅ 完成 | 自写的块级解析（标题/列表/表格/代码围栏/引用/分割线），行内样式交给 `AttributedString` |
| 语法高亮 | ✅ 完成 | Swift / Python / JS / TS / JSON / Bash，正则四类着色 |
| 深色模式 | ✅ 完成 | 跟随系统 |
| API Key 存储 | ✅ 完成 | Keychain，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| SSE 流式解析 | ✅ 代码完成，未真实验证 | 见 §2.1 |
| 请求构造与错误映射 | ✅ 代码完成，未真实验证 | 401/402/429/400 有中文提示 |
| 发送 / 停止 | ✅ 完成 | 流式中发送键变停止键 |
| 设置页 | ✅ 完成 | Key、默认模型、两个默认开关 |
| 会话持久化 | ✅ 完成 | SwiftData，消息以原始协议块 JSON 存储，重启不丢 |
| 会话列表真实数据 | ✅ 完成 | `@Query` 驱动，按更新时间倒序 |
| 新会话 / 切换会话 | ✅ 完成 | 新建、点选切换、滑动删除 |
| 图片上传 | ❌ 未开始 | `+` 按钮空实现 |
| 文档上传（PDF/DOCX） | ❌ 未开始 | |
| 语音输入 / 朗读 | ❌ 未开始 | |
| Mermaid 图表 | ❌ 未开始 | 计划 `WKWebView` + 本地 js |
| 引用角标弹层 | ⚠️ 代码已写，未验证 | 模拟器点不了，需要真机或 UI 测试 |
| 真机签名 | ❌ 未开始 | 还没在真机上跑过 |

### 2.1 唯一的关键未验证项

`ChatClient` 的流式解析按官方文档写的，但**没有用真实 Key 跑过一次**。验证时重点看三件事：

1. 请求头是否需要 `anthropic-version`。当前没有带，官方文档的 Messages 示例里也没出现。如果返回 400，先补这个头。
2. 事件顺序是否和文档一致（`message_start` → 块事件 → `message_delta` → `message_stop`）。
3. `content_block_start` 里 `server_tool_use` 的 `input` 结构和 `kind` 字段。

验证方法：把 Key 存到 `.secrets/api-key`（已在 `.gitignore` 里），然后

```bash
IPAD=9C061938-493B-4BB4-BF5D-56EA001E774D
xcrun simctl terminate $IPAD com.ruakiu.ipadds
env SIMCTL_CHILD_DS_API_KEY="$(cat .secrets/api-key)" \
    SIMCTL_CHILD_DS_AUTO_PROMPT="用一句话说明你能做什么" \
    xcrun simctl launch $IPAD com.ruakiu.ipadds
sleep 12
xcrun simctl io $IPAD screenshot shots/verify-stream.png
```

---

## 3. 架构

```
ChatView (SwiftUI)
    │  @Observable 状态
ChatViewModel          流事件 → 内容块数组
    │  AsyncThrowingStream<StreamEvent>
ChatClient             URLSession.bytes → SSEParser → 事件解码
    │
KeychainStore          API Key
```

### 文件职责

| 路径 | 职责 | 行数 |
|---|---|---|
| `Sources/App/DSApp.swift` | 入口，调试钩子注入 Key | 18 |
| `Sources/App/RootView.swift` | 双端布局分支（`horizontalSizeClass`） | 89 |
| `Core/Models/ContentBlock.swift` | 协议块模型 + `RenderBlock` 分组 | 173 |
| `Core/Models/Conversation.swift` | 会话数据（暂时是假数据） | 41 |
| `Core/Models/SampleData.swift` | 预览用样例回复 | 145 |
| `Core/Network/ChatClient.swift` | 请求构造、SSE 解码、错误映射 | 360 |
| `Core/Network/SSEParser.swift` | 按行攒事件 | 54 |
| `Core/Storage/KeychainStore.swift` | Key 存取 | 61 |
| `Features/Chat/ChatViewModel.swift` | 流式状态机 | 202 |
| `Features/Chat/ChatView.swift` | 对话页 + 输入条 | 313 |
| `Features/Conversations/ConversationSidebar.swift` | iPad 侧栏 | 49 |
| `Features/Settings/SettingsView.swift` | 设置 | 89 |
| `UI/Blocks/BlockView.swift` | 各内容块的视图 | 258 |
| `UI/Markdown/MarkdownParser.swift` | 块级 Markdown 解析 | 212 |
| `UI/Markdown/MarkdownView.swift` | Markdown 渲染 + 代码块 + 表格 | 295 |
| `UI/Markdown/SyntaxHighlighter.swift` | 正则语法高亮 | 86 |
| `UI/Theme/Theme.swift` | 颜色与间距常量 | 17 |

### 三个必须知道的决策

**协议用 Anthropic Messages 格式**（`POST /anthropic/v1/messages`），不用 Chat Completions。原因：思考、联网、引用、会话标题、安全审核在这个格式里都是一等参数，内容块结构和 UI 要渲染的东西一一对应；多轮"继续生成"在 Chat Completions 下要走 beta 接口加 `prefix: true`。

**多轮历史必须原样回传块，不能只回传纯文本。** 官方明确要求保留 `kind` 和 `signature`，阅读链接的网页正文就加密存在 `signature` 里，丢了之后用户在下一轮问"刚才那个网页"模型会答不上来。

> ⚠️ **当前代码违反这一条**：`ChatViewModel.persistLastAssistant()` 只把正文文本塞回历史。这是第一版为了跑通链路的简化，**必须在做持久化之前修掉**，否则多轮会静默丢上下文。修法：`ChatClient` 解码时连同原始 JSON 一起带出来，历史里存原始块数组。

**工程文件手写**（`iPadDS.xcodeproj/project.pbxproj`，objectVersion 77）。用 `PBXFileSystemSynchronizedRootGroup` 指向 `Sources`，所以**新增 `.swift` 文件不用改工程文件**，放进目录就会被编译。根目录的 `project.yml` 是 XcodeGen 配置，当前没在用（brew 装不上、GitHub 直连超时）。

---

## 4. 怎么跑

```bash
./Scripts/build.sh                          # 编译到 iPad 模拟器
./Scripts/shot.sh <udid> shots/xxx.png      # 装、启动、截图
```

| 设备 | UDID |
|---|---|
| iPad Pro 13 M4 | `9C061938-493B-4BB4-BF5D-56EA001E774D` |
| iPhone 16 Pro | `F07ADD5C-2F69-4851-A64E-0A8358CA3F0D` |

### 调试钩子

模拟器是 headless 的（没有窗口），点击只能靠环境变量。前缀必须是 `SIMCTL_CHILD_`。

| 变量 | 作用 |
|---|---|
| `DS_API_KEY=sk-...` | 启动时写入 Keychain，跳过手动输入 |
| `DS_AUTO_PROMPT=文字` | 启动即发一条消息，用于端到端验证 |
| `DS_SHOW_SETTINGS=1` | 启动直接打开设置页 |
| `DS_START_IN_CHAT=1` | 窄屏跳过会话列表直接进对话 |
| `DS_EXPAND_THINKING=1` | 思考块默认展开（截展开态用） |
| `DS_EXPAND_SEARCH=1` | 搜索结果默认展开 |

```bash
env SIMCTL_CHILD_DS_SHOW_SETTINGS=1 xcrun simctl launch <udid> com.ruakiu.ipadds
xcrun simctl ui <udid> appearance dark          # 切深色
```

**横屏截图拿不到**，原因和四条失败路径记在 `BUILD_NOTES.md`。要看横屏得在 Xcode 里 ⌘R 然后 ⌘← 旋转。

### 推代码

仓库：https://github.com/BOXIFAN/DeepSeek_iPad （公开，默认分支 `main`）

`github.com:22` 直连不通，remote 用 443 上的 SSH：

```
ssh://git@ssh.github.com:443/BOXIFAN/DeepSeek_iPad.git
```

仓库级 `core.sshCommand` 已配好（绕过 known_hosts 写不进工作区外的问题），`git push` 直接可用。

本机私钥带口令，**重启后需要解锁一次**：

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

`api.github.com` 直连可通，`github.com` 网页走系统代理（首字节约 13 秒）。

---

## 5. 开发日志

### 2026-11-24 · 第 1 轮：可行性与技术方案

**目标**：判断"Swift 原生 + VS Code"能不能完成这个项目。

**环境实测**：macOS 27.2.1 / arm64，只有 Command Line Tools（Swift 6.4.2），没有 Xcode、没有 iOS SDK、没有签名身份。结论是能做，但装 Xcode 是唯一硬阻塞。

**查了 API 现状**：主力模型 `deepseek-flash`（1M 上下文 / 384K 输出 / 支持图像理解）和 `deepseek-v4-pro`。官方把"全家桶应用 API"放出来了：联网搜索、文件解析、OCR、ASR、TTS、会话标题、内容安全。功能层面能覆盖官方 App。

**产出**：`docs/TECH_PLAN.md`，10 节，含协议对比、内容块映射、数据模型、里程碑拆分。

**确定的边界**：只自己用、无后端、Key 存 Keychain。

### 2026-11-24 · 第 2 轮：工程搭建与界面预览

**目标**：先出真实渲染的界面预览，而不是设计稿。

**做了什么**：装 iOS 27.2 模拟器 runtime（8.3 GB ×2 份）；手写 pbxproj；造了一份按真实块顺序组织的样例回复（思考 → 搜索 → 3 条结果 → 再思考 → 打开网页 → 带引用正文 → 表格 → 代码块）；写内容块渲染器、Markdown 解析器、语法高亮。出 iPad 与 iPhone 的浅色/深色截图。

**踩坑（三个，都记进 BUILD_NOTES）**：

1. DerivedData 默认写 `~/Library/Developer`，在工作区外 → `-derivedDataPath .build/DerivedData`
2. Swift 模块缓存写 `/var/folders`，沙盒拒绝 → `TMPDIR` 和 `CLANG_MODULE_CACHE_PATH` 重定向到 `.build/`
3. Swift 编译器用 `sandbox-exec` 隔离宏插件，沙盒里不能嵌套 → `OTHER_SWIFT_FLAGS = -disable-sandbox`

第三条最阴：它让 `@State` 展开失败，错误却伪装成 `self is immutable` 这种语法错误。

**另一个坑**：XcodeGen 装不上（brew 的 `/opt/homebrew/Cellar` 权限问题，GitHub 直连下载 release 超时），所以改成手写 pbxproj。

### 2026-11-24 · 第 3 轮：视觉向官方靠

**目标**：用户选"更贴近 DeepSeek 官方"，磨掉初版的痕迹。

**改动**：去掉消息顶部的模型标签和底部 token 用量；搜索的调用块与结果块按 `tool_use_id` 合组成一条折叠行（「搜索 2 个关键词 · 3 个结果 ›」）；模型自己打开的网页从卡片降级成一行轻提示；代码块接入正则语法高亮；输入条加「深度思考」「联网搜索」两个胶囊开关；块间距 14→12、正文行距 4→3；表格从 `fixedSize` 改成撑满宽度，表头单行缩放不折行。

### 2026-11-24 · 第 4 轮：横屏（失败，已记录）

**目标**：补横屏截图。

**四条路全部走不通**：

| 尝试 | 结果 |
|---|---|
| `simctl ui` | 只有 appearance / 对比度 / 字号 |
| `simctl io screenConfig geometry 2752x2064` | `No mode found that supports size` |
| UI 测试 `XCUIDevice.orientation` | framebuffer 变 2752×2064，但 UIKit 不重排，转正后和竖屏像素级一样 |
| Info.plist 只声明横屏 | 照旧竖屏渲染 |

**根因**：Xcode 27 移除了 `Simulator.app`（`Contents/Developer/Applications/` 整个目录没了），替代的 `DeviceHub.app` 只做设备管理。没有显示管线，headless 模拟器只剩竖屏 framebuffer。

**副产物**：UI 测试要创建伪终端，默认沙盒报 `Pseudo Terminal Setup Error`，需要 `danger-full-access` 才能跑。

**用户自己验证了横屏**（Xcode 里 ⌘R + ⌘←），布局正常，这张图确认了双栏在 1376pt 下的表现。**结论：横屏代码没问题，只是我这边拍不到。**

**回退**：UI 测试 target、`requestGeometryUpdate` 钩子、`Info.plist` 限制全部撤掉，工程保持单 target 干净。

### 2026-11-24 · 第 5 轮：功能层第一版

**目标**：把界面接到真实 API 上。

**产出**：

- `KeychainStore`：Key 存取删，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- `SSEParser`：按行攒 `event:`/`data:`，空行分发，忽略 `:` 开头的 keep-alive 注释
- `ChatClient`：`URLSession.bytes` + `AsyncThrowingStream`，解 `message_start` / `content_block_*` / `message_delta` / `message_stop`，含 `failure` 流内错误事件；HTTP 错误按 401/402/429/400 给中文提示
- `ChatViewModel`：按协议 `index` 维护块数组，`blockStart` 追加、`blockDelta` 按类型拼接、`blockStop` 给思考块补用时；`streamTick` 驱动滚动跟随
- `ChatView`：消息列表、空态、错误横幅、发送/停止、设置入口
- `SettingsView`：Key 输入、模型选择、两个默认开关
- 调试钩子：`DS_API_KEY` / `DS_AUTO_PROMPT` / `DS_SHOW_SETTINGS`

编译通过，空态和设置页截了图（`shots/ipad-empty.png`、`shots/ipad-settings.png`）。

**遗留**：真实流式未验证（等 Key）；历史只回传纯文本（见 §3 的警告）；会话不落盘。

### 2026-11-24 · 第 6 轮：仓库上线 GitHub

**产出**：https://github.com/BOXIFAN/DeepSeek_iPad ，公开仓库，首次提交 `944e0b2`，35 个文件（源码 17 个、文档 3 份、脚本 2 个、截图 8 张、工程文件 2 个）。

**过程中的四个障碍**：

1. `gh` CLI 没装，装它也绕不开认证
2. 本机没有可用凭据（无 credential helper、无 `.git-credentials`、Keychain 无记录）
3. `github.com:22` 直连不通，`github.com:443` 直连也超时，只有 `ssh.github.com:443` 与 `api.github.com` 直连可达
4. 私钥带口令（`aes256-ctr`），非交互环境无法签名；`ssh-add --apple-use-keychain` 解锁一次后可正常使用

**处理**：remote 用 `ssh://git@ssh.github.com:443/...` 形式（端口写在 URL 里，不改 `~/.ssh/config`）；提交邮箱从学号改成 GitHub 主邮箱 `3474189100rua@gmail.com`，只改仓库级配置不影响其他项目；远端那个 2 行的 `Initial commit` README 被 force 覆盖。

### 2026-11-24 · 第 7 轮：历史原样回传 + 会话持久化

**目标**：把 §6 的第 2、3 项做掉，让 App 从「能看样例」变成「能记住对话」。

**历史回传**（§3 里标警告的那条）：

- `StreamEvent.blockStart` 带出 `content_block_start` 的原始 JSON
- 回传时用模板骨架 + 最终文本覆盖，`signature_delta` 单独累积后写回
- 这样 `web_search_tool_result.encrypted_content`、`web_fetch_tool_result.signature` 都原样送回，下一轮模型还能引用读过的网页

**持久化**：

- `StoredConversation` / `StoredMessage`，消息内容存 `blocksJSON`（原始协议块数组），不做结构化建模
- `ConversationStore` 负责增删查改，本地库打不开时退化为内存存储而不是崩溃
- 侧栏改成 `@Query` 驱动真实数据，支持点选切换、新建、滑动删除
- `ContentBlock.make` 抽成共用解码，流式与历史加载同一套字段解释

**验证**（手上没有真 Key，用假 Key 走通链路）：发送 → 401 → 错误横幅 → 会话落盘 → 重启 → 会话与消息仍在。过程中发现并修掉一个 bug：标题只在内存里设了没落库，重启后退回「新对话」。

提交 `46d01ff`。

---

## 6. 下一步

按优先级排，理由是不解决前两条，后面的工作会在错误的基础上返工。

1. **真实流式验证**（阻塞中，需要 Key）—— 确认协议契约，见 §2.1
2. **修历史回传**：`ChatClient` 解码时带出原始块 JSON，`ChatViewModel.history` 存原始数组。这是多轮正确性的前提。
3. **SwiftData 持久化**：会话、消息落盘，侧栏换成真实数据，支持新建 / 切换 / 删除 / 重命名。
4. **真实数据下的渲染修整**：`ContentBlock.grouped` 现在每次 body 求值都重算；流式下 Markdown 每段全量重解析；thinking 块可能几千字，展开会把正文顶出屏幕。这三处等真实数据出来再定改法。
5. 图片与文档上传（`POST /files` 拿 `file_id`，注意 `purpose` 字段必须放在 `file` 之前）
6. 语音（ASR / TTS）
7. Mermaid、引用弹层验证、会话列表卡片化

---

## 7. 已知限制

| 限制 | 影响 | 应对 |
|---|---|---|
| 模拟器无法横屏截图 | 横屏验证要靠 Xcode GUI | 见 BUILD_NOTES |
| 模拟器 headless | 点不了界面，交互验证靠环境变量或 UI 测试（需提权） | 尽量把状态做成可注入 |
| App 进后台被挂起 | 长回复流会被切断 | 后续用 `beginBackgroundTask` 争取约 30s |
| 用过联网工具的回复不能续写 | 「继续生成」要禁用 | 判断历史里有无工具块 |
| 单条消息的 `file_id` 历史完整保留 | 长会话上下文膨胀 | 显示 token 占用，提示新建会话 |
| 免费 Apple ID 签名 7 天过期 | 真机隔周要重签 | 长期用建议 $99 账号 |

---

## 8. 文档地图

| 文件 | 内容 |
|---|---|
| `docs/DEVELOPMENT.md` | 本文件。目标、进度、日志、下一步 |
| `docs/TECH_PLAN.md` | 技术方案：环境、选型、内容块映射、数据模型、UI 结构、里程碑 |
| `docs/BUILD_NOTES.md` | 环境坑：三个沙盒限制的解法、横屏为什么拍不到、构建命令 |
| `Scripts/build.sh` | 编译（已内置必需的 `TMPDIR` 环境变量） |
| `Scripts/shot.sh` | 装 + 启动 + 截图 |
| `shots/` | 各阶段截图，文件名可读 |

## 9. 协作约定

- 改动重要文件前先说明方案，等确认
- 每轮改动前备份原文件（`.build/project.pbxproj.bak` 就是这个用途）
- 代码里 `TODO(...)` 标注的是有意的欠账，带里程碑编号
- 视觉决策已定：向 DeepSeek 官方靠，克制、少装饰
- **每轮有实质进展，在本文件 §5 追加一条日志，并更新文件头的「最后更新」日期**
