# iPad-DS 开发文档

> 这是本项目的入口文档。新对话接手时**先读这一份**，再用 `docs/TECH_PLAN.md` 查方案细节、`docs/BUILD_NOTES.md` 查环境坑。
>
> 最后更新：2026-11-25

---

## 1. 项目是什么

用 Swift 原生写一个 iPhone / iPad 通用的 DeepSeek 客户端，替代官方 App 的日常使用。

| 项 | 值 |
|---|---|
| App 显示名 | **鲸语**（bundle id 仍是 `com.ruakiu.ipadds`，改名不影响已存数据） |
| 设备 | iPad Pro 13" (M4)、iPhone 16 Pro，均为 iOS 27 |
| 分发范围 | 只自己用，不上架 |
| 后端 | 没有。客户端直连 `api.deepseek.com` |
| API Key | 存本机 Keychain，不进代码、不进 git |
| 最低部署目标 | iOS 18.0 |
| 当前代码量 | 38 个 Swift 文件，7615 行 |

**不做的事**：多用户、云同步、账号体系、计费、上架审核相关内容。这些在"只自己用"的前提下都没有意义，加进来只会拖慢进度。

---

## 2. 当前状态

一句话：**界面已按浮岛骨架重建，流式、持久化、余额、用量统计与文件读取都在；实机已跑通，最近两轮补了余额刷新调度、三项用量指标和文件上传解析。**

### 功能矩阵

| 能力 | 状态 | 说明 |
|---|---|---|
| 双端浮岛骨架 | ✅ 完成 | 对话即首页，正文 660 居中；历史收进浮层，iPad 左侧抽屉（0.28s 滑入）、iPhone 半屏 sheet |
| 内容块渲染器 | ✅ 完成 | 思考折叠、搜索合并条、结果卡片、网页提示、引用角标、表格、代码块 |
| Markdown 渲染 | ✅ 完成 | 自写的块级解析（标题/列表/表格/代码围栏/引用/分割线），行内样式交给 `AttributedString` |
| 语法高亮 | ✅ 完成 | Swift / Python / JS / TS / JSON / Bash，正则四类着色 |
| 深色模式 | ✅ 完成 | 跟随系统 |
| API Key 存储 | ✅ 完成 | Keychain，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| SSE 流式解析 | ✅ 已验证 | mock 与实机都跑过；按字节切行保留空行，第 10 轮修复 |
| 请求构造与错误映射 | ✅ 已验证 | 401/402/429/400 有中文提示 |
| 发送 / 停止 | ✅ 完成 | 流式中发送键变停止键 |
| 设置页 | ✅ 完成 | Key、默认模型、两个默认开关、系统提示词、技能 |
| 系统提示词 | ✅ 完成 | 设置里一段全局 system，随每次请求发送 |
| 思考强度 | ✅ 完成 · 已验请求体 | 关闭 / 低 / 标准 / 高，映射 `output_config.effort`；输入条胶囊可直接改 |
| 技能 | ✅ 完成 · 文件导入未实测 | 本地指令库，可多选启用；支持手写或从 Markdown 导入（解析 frontmatter） |
| 内置技能 | ✅ 完成 · 默认可选 | 「结论先行」「术语注解」随 App 安装，**默认不启用**，输入条技能胶囊决定用不用 |
| 技能进入请求 | ✅ 已验证 | 与默认提示词拼成 `system`，mock 抓包确认；停用的技能不进 |
| 流式解析 | ✅ 已验证（第 10 轮修复） | 按字节切行保留空行；mock 16 个事件全部还原 |
| 落库与重启回读 | ✅ 已验证 | mock 回复落库，重启后会话与内容都在 |
| 会话持久化 | ✅ 完成 | SwiftData，消息以原始协议块 JSON 存储，重启不丢 |
| 会话列表真实数据 | ✅ 完成 | `@Query` 驱动，按更新时间倒序，浮层里滑动删除 |
| API 余额查询 | ✅ 完成 · 实机已验证 | `GET /user/balance`；iPad 左下角卡片、iPhone 输入条右侧胶囊、明细弹层 |
| 余额刷新调度 | ✅ 完成 · mock 验证 | 失败退避重试（5/15/45/120 秒）、回前台补刷、网络恢复补刷、3 分钟周期；失败保留旧值不泛橙 |
| 会话用量 | ✅ 完成 · mock 验证 | 剩余上下文 / 缓存命中 / tok/s，输入条下方一行；点击看明细；随消息落库，切换会话能恢复 |
| 新会话 / 切换会话 | ✅ 完成 | 新建、点选切换、滑动删除 |
| 图片识别 | ✅ 完成 · 已验请求体 | 输入条选图（最多 4 张）、预览删除、气泡展示；压到 1280 长边 JPEG 0.75 后走 `image` 块 |
| 文件读取 | ✅ 完成 · mock 已验证 | 文件入口选 PDF / Word / PPT / 文本 / 代码 / 表格 / 电子书，统一 `POST /files` 拿 `file_id`；`document` 块引用，自动带 `anthropic-beta`；上传失败可点卡片重试 |
| 语音输入 / 朗读 | ❌ 未开始 | |
| Mermaid 图表 | ❌ 未开始 | 计划 `WKWebView` + 本地 js |
| 引用角标弹层 | ⚠️ 代码已写，未验证 | 模拟器点不了，需要真机或 UI 测试 |
| App 图标 | ✅ 完成 | 米白底深墨剪影蓝鲸（负空间眼睛 / 鳍线 / 水滴），`Assets.xcassets/AppIcon` 单尺寸 1024；主屏 60/76pt 已验证 |
| 真机签名 | ✅ 已完成 | 已装真机并实机测试；步骤见 `docs/DEVICE.md`，免费账号 7 天有效 |

### 2.1 传输链路已验证（mock + 实机），usage 字段待对真值

第 10 轮用本地 mock 把整条链路跑通：请求体、SSE 解析（16 个事件）、渲染、落库、重启回读。第 19 轮之前用户实机确认「基本可用」，真实请求、流式、余额都已跑过。继续对官方返回的重点是四件事：

1. 官方 `content_block_start` 里 `server_tool_use` 的 `input` 结构和 `kind` 字段，是否和 mock 假设的一致。
2. 联网搜索时 `web_search_tool_result` 的 `encrypted_content` / `signature` 能否原样回传（第 7 轮实现的，没跑过真的）。
3. `message_delta` 里的 `title` 字段（会话标题）是否真的会来。
4. **usage 的真实口径**：`/anthropic/v1/messages` 的 `input_tokens` 按 Anthropic 语义应只算未命中部分，DeepSeek 原生 `prompt_tokens` 却含命中量。`Usage.inputIncludesCache` 两种都接：看到 `prompt_cache_hit_tokens` 才按原生口径合并。实机跑一轮后核对「本轮输入」是否等于上下文规模，偏差大就说明兼容层用了另一套。

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
| `Sources/App/DSApp.swift` | 入口，调试钩子注入 Key | 19 |
| `Sources/App/RootView.swift` | 浮岛骨架：顶栏、历史浮层、余额卡位置、输入区 / 用量条 / 待发文件条 | 975 |
| `Core/Models/ContentBlock.swift` | 协议块模型 + `RenderBlock` 分组 | 166 |
| `Core/Models/ContentBlock+Decode.swift` | 块字段解码 | 109 |
| `Core/Models/MessageDocument.swift` | 文档模型、扩展名判定、`purpose` 选择、待发状态 | 187 |
| `Core/Models/ModelCatalog.swift` | 模型上下文窗口表 | 31 |
| `Core/Models/SessionMetrics.swift` | 会话用量（剩余上下文 / 缓存命中 / 速度）与格式化 | 102 |
| `Core/Models/SampleData.swift` | 预览与截图用的样例回复 | 145 |
| `Core/Models/StoredSkill.swift` | 技能模型、Markdown frontmatter 解析、system 组装 | 119 |
| `Core/Network/ChatClient.swift` | 请求构造、SSE 解码、usage 解析、错误映射 | 388 |
| `Core/Network/SSEParser.swift` | 按行攒事件 | 54 |
| `Core/Network/BalanceClient.swift` | 余额查询（`Bearer` 鉴权）、网络错误分类 | 153 |
| `Core/Network/FileUploader.swift` | multipart 上传（`purpose` 在 `file` 前）、错误映射 | 217 |
| `Core/Storage/KeychainStore.swift` | Key 存取 | 61 |
| `Core/Storage/ConversationStore.swift` | 会话增删查改 | 88 |
| `Core/Storage/StoredModels.swift` | SwiftData 模型（`usageJSON` 存每轮用量、`attachmentsJSON` 存附件元数据） | 106 |
| `Core/Storage/BalanceStore.swift` | 余额状态、周期刷新、退避重试、网络恢复补刷 | 278 |
| `Core/Storage/BalanceRetryPolicy.swift` | 余额重试退避表与可重试判定 | 35 |
| `Core/SelfTest.swift` | 离线自检（113 条） | 511 |
| `Features/Chat/ChatViewModel.swift` | 流式状态机 + 用量计量 + 附件进请求体 | 511 |
| `Features/Chat/ChatView.swift` | 对话流、空态建议卡、悬浮输入条（图片 + 文件入口）、模式胶囊 | 532 |
| `Features/Conversations/ConversationSidebar.swift` | 历史浮层，iPad 抽屉与 iPhone sheet 共用 | 204 |
| `Features/Settings/SettingsView.swift` | 设置入口，导航到提示词与技能 | 179 |
| `Features/Settings/SystemPromptView.swift` | 系统提示词编辑 | 49 |
| `Features/Settings/SkillsView.swift` | 技能列表、导入、编辑 | 278 |
| `UI/BalanceCard.swift` | 余额卡片、手机端胶囊、明细弹层 | 214 |
| `UI/SessionMetricsBar.swift` | 会话指标条与用量明细弹层 | 244 |
| `UI/DocumentChip.swift` | 已发送文件卡、待发文件卡（上传中 / 就绪 / 失败） | 143 |
| `UI/Blocks/BlockView.swift` | 各内容块的视图 | 258 |
| `UI/Markdown/MarkdownView.swift` | Markdown 渲染 + 代码块 + 表格（可选衬线排印） | 334 |
| `UI/Markdown/MarkdownParser.swift` | 块级 Markdown 解析 | 212 |
| `UI/Markdown/SyntaxHighlighter.swift` | 正则语法高亮 | 86 |
| `UI/Theme/Theme.swift` | 品牌色与正文宽度 | 9 |
| `Sources/Assets.xcassets/AppIcon.appiconset` | 1024 单尺寸 App 图标 | — |

### 三个必须知道的决策

**协议用 Anthropic Messages 格式**（`POST /anthropic/v1/messages`），不用 Chat Completions。原因：思考、联网、引用、会话标题、安全审核在这个格式里都是一等参数，内容块结构和 UI 要渲染的东西一一对应；多轮"继续生成"在 Chat Completions 下要走 beta 接口加 `prefix: true`。

**多轮历史必须原样回传块，不能只回传纯文本。** 官方明确要求保留 `kind` 和 `signature`，阅读链接的网页正文就加密存在 `signature` 里，丢了之后用户在下一轮问"刚才那个网页"模型会答不上来。

> 第 7 轮已按这条修完：`ChatClient` 解码时带出 `content_block_start` 的原始 JSON，`ChatViewModel` 用模板骨架 + 最终文本还原，`signature_delta` 单独累积后写回。现在历史里存的是原始块数组。

**工程文件手写**（`iPadDS.xcodeproj/project.pbxproj`，objectVersion 77）。用 `PBXFileSystemSynchronizedRootGroup` 指向 `Sources`，所以**新增 `.swift` 文件不用改工程文件**，放进目录就会被编译。根目录的 `project.yml` 已在第 18 轮删除：XcodeGen 始终没装上，`pbxproj` 是唯一工程来源。

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
| `DS_SHOW_HISTORY=1` | 启动直接拉出会话历史浮层 |
| `DS_SHOW_BALANCE=1` | 启动直接打开余额明细 |
| `DS_SHOW_USAGE=1` | 启动直接打开会话用量明细 |
| `DS_PENDING_DOCUMENT=1|failed|uploading|multi` | 待发文件条的各种状态，截图用 |
| `DS_DEMO_DOCUMENT=1` | 配合 `DS_DEMO_THREAD`，给演示对话挂一个文档附件 |
| `DS_UPLOAD_FILE=demo|<文件名>` | 启动后把 Documents 里的文件（`demo` 为内置测试 PDF）走真实上传 |
| `DS_SEND_AFTER_UPLOAD=1` | 文件就绪后自动带上附件发出 `DS_AUTO_PROMPT` |
| `DS_START_EMPTY=1` | 不进任何会话，停在空态 |
| `DS_DEMO_THREAD=1` | 灌入一段示例对话（`SampleData`），不写库 |
| `DS_DEMO_HISTORY=1` | 历史浮层用五条演示条目，不动 SwiftData |
| `DS_BALANCE_DEMO=1` | 余额卡填 ¥14.41 的演示值，截图用 |
| `DS_SETTINGS_PAGE=prompt|skills` | 打开设置后直接进对应子页 |
| `DS_API_BASE=http://127.0.0.1:8710` | 把聊天与余额请求指到本地 mock |
| `DS_SELFTEST=1` | 跑离线自检，结果写到沙盒 `Documents/selftest.txt` |
| `DS_SLOW_ANIM=1` | 抽屉动画放慢到 4 秒，方便逐帧截图 |
| `DS_DEMO_IMAGE=1` | 配合 `DS_AUTO_PROMPT` 发一条带测试图的请求 |
| `DS_PENDING_IMAGE=1` | 只在输入条挂一张待发图，不发送，截预览条用 |
| `DS_SWITCH_DURING_STREAM=1` | 发完消息 1.2 秒后自动新建会话，验「流式中切会话不串台」 |
| `DS_SHOW_GALLERY=1` | 直接打开全屏图片流（3 张测试图） |
| `DS_IMAGE_PROGRESS=1` | 显示一个假的压缩进度条，截进度态用 |
| `DS_PRINT_SYSTEM=1` | 把拼好的 system 写到沙盒 `Documents/system-prompt.txt` |
| `DS_MEMORY_STORE=1` | 整个数据库只用内存，截图演示不碰真实数据 |
| `DS_EXPAND_THINKING=1` | 思考块默认展开（截展开态用） |
| `DS_EXPAND_SEARCH=1` | 搜索结果默认展开 |

浮岛骨架的整套验收图（空态 / 对话 / 历史 / 余额明细 / 设置 / 深色，双端各一套）：

```bash
./Scripts/preview-shots.sh
```

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

### 2026-11-24 · 第 8 轮：四个界面方向 → 定下浮岛 → 余额卡片

**目标**：界面骨架还没定，先做几套能看的选择，再按选中的那套重构。

**四个方向**（`Sources/Explore/`，`DS_UI_VARIANT` 切换）：

| 代号 | 骨架 | 结论 |
|---|---|---|
| `paper` | 标签条 + 620 宋体正文 + 285 边注 | 读长文最好，iPad 信息位最全 |
| `floating` | 单栏 660 + 悬浮输入 + 顺手历史 | **用户选中** |
| `desk` | 232 / 528 / 272 三栏 + 本轮上下文与费用 | 信息量最大，用户判断「过重」 |
| `cards` | 一轮一卡 + 左侧问题轴 | 适合回看与转发 |

四套都拍了 iPad 与 iPhone 各一张，对比页在 `explore/compare.html`。

**重构**：`RootView` 从 `NavigationSplitView` 换成单栏浮岛。

- 顶栏三件套：历史按钮、会话标题（无会话时显示 DeepSeek）、新对话
- 正文 660 居中，空态换成四张建议卡（点了填进输入框，不直接发）
- 输入条常驻底部，上方两个模式胶囊；手机端右侧多一枚余额胶囊
- 历史改成浮层：iPad 左侧 320 宽抽屉，iPhone 半屏 sheet；`HistoryItem` 与 SwiftData 解耦，演示数据也能喂
- 深色模式全部走系统语义色，浮岛背景是深底渐变

**余额卡片**（用户从 DSH 的侧栏卡片提的需求）：

- `BalanceClient`：`GET https://api.deepseek.com/user/balance`，`Authorization: Bearer`，和聊天的 `x-api-key` 不是同一个头
- `BalanceStore`：全局一份，启动、发送结束、手动点击时刷新；60 秒内不重复请求
- iPad 左下角 150 宽卡片（金额 + 状态 + 刷新），手机端输入条右侧胶囊，点开明细弹层（总额 / 赠送 / 充值 / 刷新 / 去设置）
- 低于 ¥20 转橙色并提示充值，错误态点击卡片直接进明细

**踩坑**：

1. `safeAreaInset(edge: .bottom)` 里的 `FloatingComposer` 只按 ideal 宽度布局，`.frame(maxWidth: 660)` 不生效，输入条挤到左下角、被余额卡压住。改成外层 `VStack` + 显式 `frame(maxWidth:)` 再居中。
2. 历史浮层用 `.regularMaterial` 在白底上几乎透明，后面正文透出来。换成不透明 `systemBackground` + 阴影。
3. `BalanceStore.note` 先判断 `hasKey` 会让 demo 快照显示「还没填 API Key」，改成先看有没有结果。

**验证**：

- 不带 demo 启动，能加载最近一条会话并渲染 → 真实路径通
- 余额请求打到了真实接口，返回 401。本机用 curl 复核过：无 Key 与假 Key 都是 401，`/user/balance` 端点本身正确。**手上 Key 已失效，成功态没跑到**
- 截图在 `shots/redesign/`，用 `./Scripts/preview-shots.sh` 重拍

### 2026-11-24 · 第 9 轮：系统提示词与技能

**目标**：让用户能固定一段全局 system，并把「技能」这种可复用指令存下来按需启用。

**做了什么**：

- `ChatClient.Options` 加 `systemPrompt`，请求体带 `system` 字段（Anthropic 格式允许字符串）
- `PromptComposer`：默认提示词在前，启用的技能逐个拼成 `# 技能：名称` + 正文，中间用 `---` 分隔；全空时返回 nil，不发送 system
- `StoredSkill`：SwiftData 模型（名称、说明、指令、启用、来源、时间戳）。加实体属于轻量迁移，实测旧会话全部保留
- `SkillParser`：拆 YAML frontmatter 的 `name` / `description`，剩下的当正文；解析不到就退回文件名 + 全文。DSH 那套 `SKILL.md` 可以直接导入
- 设置页新增「提示词」区块，两个入口都显示摘要（字数 / 已启用技能数），footer 报出拼好后的总字数
- 技能页：新建、从 Markdown 导入（`fileImporter`，支持多选）、左滑启停、滑动删除；编辑页改名称/说明/指令，开关启用，底部删除

**边界**：技能只提供指令，不执行脚本，也引用不到 App 读不到的文件。导入整份 DSH 技能时只有 `SKILL.md` 会进来，`references/` 里的东西不在包里。

**验证**：

- 编译通过；加实体后旧会话在启动时正常加载
- 截图在 `shots/redesign/`（`*-prompt.png`、`*-skills.png`）
- 导入与真实请求没有实测：headless 模拟器点不了文件选择器，手上也没有有效 Key

**为了截图不污染真实数据**，加了 `DS_MEMORY_STORE=1`（整库只走内存）与 `DS_SEED_SKILLS=1`（空库里放两条示例技能）。

### 2026-11-24 · 第 10 轮：功能验证，修掉一个一直在的流式 bug

**这轮干的事**：把上一轮做的提示词、技能、余额和浮岛骨架都跑一遍，看能不能真用。

**验证分三层**

1. **离线自检**（`DS_SELFTEST=1`，32 条断言）：技能 frontmatter 解析、提示词组装（空、只有提示词、停用技能、顺序、空白指令）、请求体构造、余额解析（正常/美元/空列表/缺字段/非 JSON）、SwiftData 写盘后重开可读
2. **本地 mock 服务**（`Scripts/mock-server.py` + `DS_API_BASE`）：抓完整请求体、回一段 SSE 流、回一份余额，验证请求 → 解析 → 渲染 → 落库 → 重启回读
3. **真实设备行为**：启动加载最近会话、无 Key 的 401 错误态、低额警示色

**发现并修掉的三个问题**

| 问题 | 影响 | 修法 |
|---|---|---|
| `URLSession.AsyncBytes.lines` 会折叠连续换行，SSE 的空行被吃掉 | **流式解析从来没工作过**：请求 200、流读完、0 个事件，界面只剩用户气泡 | 改成按字节切行，保留空行 |
| 思考块亚秒完成时显示「用时 0 秒」 | 本地 mock 下难看 | 不足 1 秒时只显示「已深度思考」 |
| `DS_START_EMPTY=1` 提前 `return` 会跳过 `DS_AUTO_PROMPT` | 调试钩子互相打架 | 改成条件跳过加载会话，不再提前返回 |

第一个是这一轮唯一的关键发现。它从第 5 轮就存在，因为一直没跑过真实流，所以每次都只看到「请求发出去了」，没有报错也没有内容。

**验证数据**

- 自检：32 passed / 0 failed
- mock 请求体：`system` = 用户提示词 + `---` + `# 技能：中文技术写作`；停用的「代码审阅」确认没有进去
- SSE：16 个事件全部还原（thinking 1 块、text 1 块、13 段 delta、message_delta、message_stop）
- 落库：assistant 消息 `status=end_turn`，重启后会话标题与正文都在
- 余额：mock 的 14.41 显示为 `¥14.41`，走的是低额橙色分支

**没验证到**

- 真实 Key：仍是 401，Keychain 里那把没换过
- 文件选择器导入：headless 模拟器点不了 `fileImporter`

**测试残留**：真实库里多了一条「链路验证：mock 落库」，在历史浮层左滑删掉即可。

### 2026-11-24 · 第 11 轮：顶栏界限与思考强度

**用户报的两个问题**

1. 顶部标题与正文没有界限，滚动时文字穿过标题区，读起来乱
2. 没有可调的思考强度

**顶栏**

原来的做法是浮层渐变背板（120pt，从 96% 白淡到透明）。标题落在渐变中段，遮罩只剩五六成不透明，正文直接透过来。

改成 `.safeAreaInset(edge: .top)`：顶栏进入布局，内容被推到下方，滚不到标题区。顶栏自己用 `.ultraThinMaterial` 打底并延伸到状态栏，底部加 0.5pt 分隔线。滚动内容被裁在分隔线以下，界限清楚。

顺带加了 `defaultScrollAnchor(.bottom)`：打开长会话直接停在最新消息，符合聊天习惯，也让「顶栏是否遮住内容」这件事在截图里可验证。

**思考强度**

查了文档，Anthropic 兼容格式里思考强度走 `output_config.effort`（low / high / max），`thinking` 只负责开关（`budget_tokens` 被忽略）。

- `ThinkingEffort` 四档：关闭 / 低 / 标准 / 高，对应不发送 / low / high / max
- 输入条的「深度思考」胶囊换成菜单：点开四档任选，胶囊直接显示当前档位
- 设置页「思考」区块改成四段选择器，附映射说明
- 请求体：`thinking: {type: enabled}` + `output_config: {effort: high}`

**验证**

- 自检 35 条全过（新增 3 条：强度进 `output_config`、关闭时不带 `output_config`、关闭时不带 `thinking`）
- mock 抓包：`{"thinking": {"type": "enabled"}, "output_config": {"effort": "high"}}`
- 截图：`shots/redesign/` 全部重拍

### 2026-11-25 · 第 12 轮：历史浮层打开动画

**问题**：iPad 的抽屉打开没有动画，瞬开。

**根因**：`showHistory = true` 直接赋值，没有动画事务；`.animation(value:)` 挂在 `if` 分支内部，分支插入时修饰符本身还没生效，抓不到这次插入。

**改法**：

1. 打开与关闭都走 `withAnimation(drawerAnimation)`
2. 抽屉常驻在视图树里（不靠 `if` 插入），由 `offset` 驱动：关闭时 `-360`（含阴影整个移出屏外），并关掉命中测试
3. 遮罩跟着 `opacity` 从 0 到 0.26 同步淡入
4. 曲线先用 `.easeOut(0.28)`，后来换成 `.spring(response: 0.30, dampingFraction: 0.86)`

**为什么换 spring**：easeOut 的第一帧就是最高速，抽屉像被弹出来的。spring 起步有加速段：

| 时间 | easeOut | spring |
|---|---|---|
| 16ms | 9.4% | 4.6% |
| 50ms | 27.8% | 30.2% |
| 100ms | 51.8% | 67.7% |
| 200ms | 88.1% | 97.6% |
| 280ms | 100% | 100.5% |

前 30ms 更轻，中段更快，峰值 1.005（过冲 0.5%，肉眼不可见）。响应时间 0.30 是为了让总时长和原来的 0.28 接近，阻尼 0.86 把过冲压到不可见。

**验证**：加了 `DS_SLOW_ANIM=1`（放慢到 4 秒）与 `DS_SHOW_HISTORY=1`（延迟 1.2 秒再打开），连拍能抓到中间帧。竖屏中间态存在 `shots/redesign/ipad-history-opening.png`：抽屉右边缘在 x≈72pt，遮罩刚起，位移和淡入都对。

**行为影响**

- 抽屉关闭后仍在视图树里（屏幕外），列表会继续跟随 `@Query` 更新，开销可忽略
- iPhone 仍是系统 sheet，动画由系统负责

### 2026-11-25 · 第 13 轮：两个内置技能

**目标**：带两个开箱可用的技能，顺便把技能链路再验一遍。

**内容**（`Sources/Core/Models/BuiltinSkills.swift`）：

| 名称 | 作用 | 字数 |
|---|---|---|
| 结论先行 | 第一句给结论，依据最多三条 | 138 |
| 术语注解 | 英文术语首次出现给中文对照 | 146 |

**安装策略**

- 首次启动装一次，版本号存在 `builtinSkillsVersion`
- 用户删掉后不会自己回来；技能页右上角菜单有「恢复内置技能」
- 列表里带「内置」灰徽章，和用户自建的条目区分开
- 内存库模式（截图用）每次都装，不写版本号，免得把真实库的首次安装挡掉

**验证**

- mock 抓包：`system` 里两段 `# 技能：结论先行` / `# 技能：术语注解`，顺序与定义一致，前面是用户的默认提示词
- 自检 40 条全过（新增 5 条：数量、名称唯一、指令长度、内置识别、自建不误判）
- 截图：`shots/redesign/ipad-skills-builtin.png`

**顺带清理**：删掉了 `DS_SEED_SKILLS` 那套演示 seed，截图改用真实的内置技能。

### 2026-11-25 · 第 14 轮：技能改成按需启用

**用户指出的问题**：内置技能装完就是 `isEnabled: true`，等于每次请求都全局注入。DSH 里技能是 `/` 显式调用或模型自行决定，不该常驻。

**改动**

1. 内置技能安装时 `isEnabled: false`
2. 输入条加「技能」胶囊：点开列出所有技能，勾选即启用，再点取消；全停用时给「全部停用」
3. 胶囊显示 `技能 · N`，启用时品牌蓝、停用时灰
4. 技能状态只有一层——胶囊和设置页改的是同一个 `isEnabled`，不做"默认值 + 本次覆盖"两套状态

**为什么不用 `/`**

- iOS 键盘上打 `/` 要切到符号页，比点胶囊慢
- 技能是持续状态（接下来几条都生效），不是单条消息的一次性命令
- 胶囊能直接显示当前启用了几个，`/` 只在输入时可见

**为什么不让模型自己决定**

DeepSeek 的 Anthropic 兼容接口支持工具调用，让模型自己"加载技能"要多一次往返，还得把技能全文塞进工具定义里，成本和可控性都不划算。自用场景里用户自己选更快。

**验证**（mock 抓包）

| 状态 | system | 技能段 |
|---|---|---|
| 默认（都不启用） | 23 字符 | 无 |
| 胶囊里勾选两个 | 343 字符 | `结论先行`、`术语注解` |

**布局**：四个胶囊挤在 iPhone 一行里，第一版把「深度思考 · 标准」压成了三行。把文案缩成「思考 · 标准」、字号 12 → 11.5、内边距 11 → 8，并给每个胶囊加 `lineLimit(1)` + `fixedSize`，现在一行放得下。

### 2026-11-25 · 第 15 轮：图片识别

**协议**：Anthropic 格式的 `image` 块，`source.type = base64`、`media_type = image/jpeg`。文档写的是 `deepseek-flash` 支持、`deepseek-v4-pro` 会把图替换成 `[Unsupported Image]`。

**实现**

- `MessageImage`：压缩后的 JPEG + 尺寸，`blockJSON` 直接生成协议块，`decode(from:)` 从历史块还原
- `ImagePipeline`：长边压到 1280、JPEG 0.75。服务端本来就会把图缩到约 1300×1300 再计费（单张上限 1024 token），客户端先压能省一半以上请求体；一张 960×640 的测试图压完 43 KB
- `ChatViewModel.send` 加 `images` 参数，消息内容拼成 `[image..., text]`，空文字也能发；落库直接存这个块数组
- `load` 时把历史里的 image 块解回 `MessageImage`，气泡照常显示
- UI：输入条左侧加选图按钮（`PhotosPicker`，最多 4 张），选完进预览条（缩略图 + 删除 + 继续加），发送后显示在用户气泡上方
- 模型是 `deepseek-v4-pro` 且有待发图时，预览条下方给一条橙色提示「不读取图片，发送前请切到 flash」

**验证**

- 自检新增 9 条：长边 ≤ 1280、输出 JPEG、体积 < 600KB、块结构（type/source/media_type/base64 非空）、解码回环、空数据不崩 → **49 条全过**
- mock 抓包：请求 2 个块，`image` 块 base64 长度 57948，解码后 43460 字节，文件头 `ffd8ffe0`（JPEG）
- 截图：`shots/redesign/ipad-image.png`（气泡）、`ipad-image-pending.png`（预览条）

**没验证到的**

- 真机的 `PhotosPicker` 选择流程：headless 模拟器点不了，代码走的是标准 API
- 模型是否真能读图：需要有效 Key

### 2026-11-25 · 第 16 轮：图片查看、压缩进度、图片流入口

**三个功能**

1. **全屏查看**：点气泡里的图进入全屏，左右滑动翻页，双击在 1x / 2.5x 之间切换，放大后可拖动（范围限制在图片边界内）
2. **压缩进度**：选图后解码 + 缩放 + 编码放到后台线程，输入条上方显示「正在处理 1/3 张」
3. **图片流入口**：顶栏在有图片的会话里多一个图片按钮，点开就是整个会话的图片，底部缩略图条可以直接跳转

**踩的坑**

- `TabView + .page` 放在 `fullScreenCover` 里会为页码指示器预留一段高度，图片只铺到 917pt（全屏 1032pt），底部留黑。换成 `ScrollView + scrollTargetBehavior(.paging) + scrollPosition(id:)`，高度自己说了算
- `GeometryReader + ignoresSafeArea` 需要给子视图显式 `frame(width:height:)`，只写 `maxWidth: .infinity` 不生效
- 缩略图条单独放 `ScrollView` 时宽度会被内容撑缩，必须由外层给定宽度

**验证**

- 全屏态：`shots/redesign/ipad-gallery.png`（图片全屏、X 在左上、`1 / 3`、底部三张缩略图）
- 进度态：`shots/redesign/ipad-image-progress.png`
- 发图后顶栏出现图片按钮：`shots/redesign/ipad-image.png`

**没验证到的**：真机上的双击缩放、滑动翻页手感——headless 模拟器点不了，逻辑只在这里跑过。

### 2026-11-25 · 第 17 轮：看图手势、保存与排序

**三个功能**

1. **下拉关闭**：全屏看图时向下拖，跟手位移、背景同步变淡；超过 140pt 或预测位移超过 320pt 松手就关，否则弹回。横向拖动不触发（比较横纵位移）
2. **长按菜单**：全屏图上长按出「保存到相册」「复制图片」，操作完顶部短暂显示一行确认。保存需要 `NSPhotoLibraryAddUsageDescription`，已写进工程的 `INFOPLIST_KEY_*`
3. **拖动排序**：待发图片长按拖动换位置，`onDrag` + `ImageCellDropDelegate`，拖动中的格子半透明，其他格子让位有 0.16s 动画

**验证**

- 构建通过，`Info.plist` 里确认有 `NSPhotoLibraryAddUsageDescription`
- 全屏看图截图无回退
- 三个手势都没有实测：headless 模拟器点不了、拖不动，逻辑只在代码层确认

**实机**：补了 `docs/DEVICE.md`，从插线、信任、选 Team 到 7 天续签和常见报错都写了。

### 2026-11-25 · 第 18 轮：清理

**删了什么**

| 目标 | 体积 | 理由 |
|---|---|---|
| `Sources/Explore/` | 80 KB / 2002 行 | 四套界面方向的首屏存档，正式版只用浮岛 |
| `explore/` | 11 MB | 方向对比页与过程截图 |
| `Scripts/explore-shots.sh` | 4 KB | 只为上面那套存档服务 |
| `shots/*.png` 11 张 | 4 MB | 旧界面截图，已被 `shots/redesign/` 取代 |
| `project.yml` | 4 KB | XcodeGen 配置，从没装上过 |
| `.tools/` | 0 B | 空目录 |

**死代码**

- `Theme.contentMaxWidth` / `userBubble` / `blockSpacing`：浮岛改用固定尺寸后没人用了
- `ContentBlock.isToolRelated`：没有调用方
- `ConversationStore.rename` / `deleteAll`：没有入口（重命名功能还没做）

入口从 `ExploreRoot()` 改回 `RootView()`。

**验证**

- 构建通过，自检 49 条全过
- 界面截图无回退（`/tmp/after-clean.png` 与清理前一致）
- 工作区从 42 MB 降到 27 MB，代码从 5612 行降到 3610 行（不含 Explore）

**注**：第 5、6 轮日志里引用的 `shots/ipad-*.png` 随这次清理删除，那几处路径不再有效；`TECH_PLAN.md` 顶部已标为立项方案，现状以本文件为准。

### 2026-11-25 · 第 19 轮：余额刷新修复 + 会话用量三项

**修的问题**：实机上余额卡片经常显示失败，要手动刷新才恢复。

根因不是接口，是调度只有两个触发点（启动、发送结束）：一次冷启动抢在网络就绪前、或者从后台回来时连接已失效，错误就停在卡片上，之后再也不会有请求。顺手发现的三个小毛病一起修了：

| 问题 | 修法 |
|---|---|
| 失败后无重试 | `BalanceRetryPolicy`：5 / 15 / 45 / 120 秒退避，401/402/403 与 4xx 不重试，429 重试 |
| 回前台不刷新 | `RootView` 监听 `scenePhase`，`.active` 时 `refreshIfStale(within: 30)` |
| 网络切换不刷新 | `BalanceStore` 内建 `NWPathMonitor`，网络恢复时补刷 |
| 后台挂起后请求取消被当成 HTTP 错误 | `BalanceError.cancelled` 单独一类，不算失败 |
| 取消旧请求时旧任务的 `defer` 会把 `isLoading` 置回 false | 改成 generation 校验，只有当前代次的请求能改状态 |
| 一次失败把金额也染成橙色、数字被错误文案盖住 | 失败保留旧快照，副标题写「HH:mm 更新 · 稍后自动重试」；金额只在低额/无 Key 时变橙 |
| 出错时点卡片只会打开明细 | 轻点直接重试，长按才看明细；卡片右上角换成重试图标 |
| `waitsForConnectivity = false` + 15 秒超时 | 改为 true，25 / 45 秒，加 `reloadIgnoringLocalAndRemoteCacheData` |
| 只有 3 分钟周期刷新 | 已有；加 `nextRetryAt`，避免周期刷新和退避连发 |

**新增三项指标**（输入框下方一行，点开明细）：

1. **上下文剩多少**：`1M 窗口 - (最近一轮输入 + 输出)`。环填剩余比例，文字报绝对 token。
2. **缓存命中**：`cache_read_input_tokens / 总输入`。Anthropic 口径按「未命中 + 命中 + 写入」算分母；DeepSeek 原生 `prompt_cache_hit_tokens` 口径不重复加。
3. **tok/s**：流式中按已生成字符 ÷（当前 - 首 token）估；结束后换成 `output_tokens ÷ 首 token 到结束`。

**协议层的改动**

- `StreamEvent.messageStart` 从无载荷改成带 `model` 与 `usage`。原来直接丢弃了 `message_start` 里的 `input_tokens` 与缓存字段，只靠 `message_delta` 拿不到输入规模。
- `Usage` 加 `cacheCreationTokens` / `inputIncludesCache` / `merge(with:)`，字段缺失时取各自有效值，不用 0 覆盖。
- `StoredMessage` 加 `usageJSON`（Optional，轻量迁移），切换会话和重启后指标能恢复。
- `ModelCatalog` 存上下文窗口（两个模型都是 1M），`SessionMetrics` 统一格式化（`972K` / `1.0M` / `88%` / `46 tok/s`）。

**顺手修的一个串台**

流式中点「新建对话」或切换会话时，旧任务的收尾会拿新的 `currentConversation` 落库、并把旧 usage 盖到新会话的指标上。`ChatViewModel` 加 `roundID` 代次：`startNew` / `load` 换一代，旧任务的事件、报错、`finish` 全部作废；请求用的 `history` 也在发送时拍快照。验证钩子 `DS_SWITCH_DURING_STREAM=1`：流式中切到新会话后，新会话保持空态、指标条是 `上下文剩 1.0M`，没有被旧轮的 `991K / 87%` 污染。

**验证**

- 自检 49 → 83 条：Usage 两套口径、两段合并、指标格式化、余量不为负、退避表、可重试判定、usage 落库回读
- mock 端到端：`上下文剩 990K · 缓存命中 87% · 301 tok/s`，和手算一致（9440 输入 / 96 输出）
- 失败重试：mock 前 1 次回 503，启动 10 秒后卡片自己恢复成 `¥14.41`，没点任何按钮
- 流式中切会话：旧任务不再改新会话的消息与指标（`DS_SWITCH_DURING_STREAM=1`）
- 重启恢复：发完一轮杀进程再启动，指标从落库的 usage 恢复成 `990K / 87%`
- 双端截图：`shots/redesign/{ipad,iphone}-usage.png`，深色模式也过了一遍

**没验证到的**：真实 API 的 usage 字段口径（本地没有可用 Key，见 §2.1）；模拟器造不出「回后台再回前台」，`scenePhase` 那条路径只能真机确认。

### 2026-11-25 · 第 20 轮：文件读取

**做成了什么**

输入条左侧新增回形针，选文件后自动上传拿 `file_id`，发送时以 `document` 块引用。PDF / Word / PowerPoint 走解析（默认 `text_recognition`，可切 `rich_layout_recognition` 保留文档里的图）；文本、代码、CSV / JSON、XLSX、EPUB 走 `user_data`，不计费。

| 环节 | 实现 |
|---|---|
| 类型判定 | 扩展名白名单 + `UTType` 兜底；图片走原来的照片入口，压缩包等直接拒绝 |
| 上传 | `POST /files`，手写 multipart，`purpose` 严格排在 `file` 之前；超时按上传 120s + 解析 120s 放宽到 180 / 300 |
| 引用 | `{"type":"document","source":{"type":"file","file_id":…}}`；请求体出现 document 块就自动带 `anthropic-beta: files-api-2025-04-14` |
| 待发状态 | 上传中 / 已就绪 / 失败三态；失败保留数据可点卡片重试；上传中与失败都禁用发送 |
| 落库 | 协议块原样进 `blocksJSON`；文件名、大小、purpose 存 `StoredMessage.attachmentsJSON`，重启后气泡与附件卡都能恢复 |
| 保留图 | 选完文件后出现开关，切换会对已解析的 PDF / Word 重传（purpose 在上传时定死） |

**协议与限制**（来自官方文件解析 / Files API 文档）

- 每轮最多 5 个文档（服务端上限 20、文档文字合计 8 MiB）。
- 大小上限：PDF / 办公文档 100 MiB，文本 / 表格 / 电子书 32 MiB。
- 上传即解析，解析成功才返回 `file_id`；失败的文档不保存不计费。
- 多轮对话里 `file_id` 的文档内容完整保留在上下文，上下文超长时返回 400，不会静默截断。

**踩的坑**

- `fileImporter` 用 UTType 白名单会漏掉 `.swift`、`.md` 这类代码与笔记文件，干脆放开到 `.item`，选完再按扩展名过滤。
- 附件元数据不能塞进协议块：原始块会原样回传，多出的字段可能被服务端拒。另开 `attachmentsJSON` 存展示信息。
- 截图钩子原本写在 `DS_DEMO_THREAD` 的 `return` 之后，永远不执行；把待发附件钩子挪到 demo 分支之前。
- 模拟器的 App 沙盒不允许从宿主 `cp` 文件进去，端到端验证改用内置测试 PDF，由 App 启动时写进自己的 Documents。

**验证**

- 自检 83 → 113 条：类型判定、purpose 选择、大小上限、multipart 字段顺序 / 文件名 / 正文 / boundary 收尾、document 块结构、上传响应解析、坏响应、beta 头判定、附件元数据落库
- mock 端到端：上传 401 字节 PDF → `file-api-mock01` → 请求体 `document` 块 + `text` 块，mock 日志确认 `beta=files-api-2025-04-14`
- 上传失败：mock 首次回 503，卡片显示「上传失败 · 点一下重试」，下方报「文档解析服务繁忙」，发送按钮变灰
- 重启恢复：发完一轮杀进程再启动，气泡里的文件卡与指标都从库里恢复
- 双端截图：`shots/redesign/{ipad,iphone}-{file,document}.png`

**没验证到的**：真实 DeepSeek 解析（PDF 版式、扫描件文字识别、`rich_layout_recognition` 裁图效果）；headless 模拟器点不了文件选择器，选文件这一步只能在真机上走。

### 2026-11-25 · 第 21 轮：App 图标

**结果**：米白底 + 深墨剪影蓝鲸，单色剪影、负空间眼睛与鳍线、背上方三滴水花，1024 单尺寸，接进 `Sources/Assets.xcassets/AppIcon.appiconset`，`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。构建后 `Info.plist` 里 `CFBundleIcons` 已生成 `AppIcon60x60` / `AppIcon76x76`，iPad 与 iPhone 主屏缩到 60pt 仍能看清鲸鱼表情。

**过程**：先试 GPT Image 2.6，代理不通（`[object Object]`）；切回本地 `moss-image-sft-8bit`。第一版是深蓝底彩色卡通鲸，用户给了剪影插画参考后改走单色剪影，第 4 版（身体流线、鳍全连体、无碎片）定稿。本地路径要设 `MOSS_MLX_CACHE` 到工作区，否则缓存写 `~/.cache` 被沙盒拒绝。候选图（悬浮卡 / 气泡波形 / 满版蓝底等 6 版）留在工作区 `icon-candidates/`，已 gitignore。

**边界**：这是 AI 生成的原创卡通鲸鱼，不复制 DeepSeek 官方 logo；自用没问题，若以后要分发，图标与展示名都要换。

### 2026-11-25 · 第 22 轮：改名「鲸语」

**原因**：自制客户端叫 DeepSeek 容易被当成官方 App，也踩品牌红线。选定 **鲸语**：图标是鲸，产品是对话，两字在主屏放得下。

**改动**

| 位置 | 从 | 到 |
|---|---|---|
| `CFBundleDisplayName`（两套配置） | DeepSeek | 鲸语 |
| 空态大标题 | DeepSeek | 鲸语 |
| 顶栏空态标题 | DeepSeek | 鲸语 |
| 输入框占位 | 给 DeepSeek 发消息 | 给鲸语发消息 |

**没动的**：bundle id `com.ruakiu.ipadds`、target / scheme `iPadDS`、`DS_*` 调试钩子、所有 `api.deepseek.com` 与模型名引用、演示数据里的「DeepSeek 模型能力与价格」。bundle id 不变，真机上 Keychain 里的 Key 与 SwiftData 会话都保留，覆盖安装即生效。

**验证**：`Info.plist` 的 `CFBundleDisplayName` 为「鲸语」；双端主屏显示「鲸语」+ 鲸鱼图标；App 内空态、顶栏、输入框文案都已切换；全套验收截图重跑。

---

## 6. 下一步

1. **核对真实 usage 口径**（§2.1 第 4 条）：实机跑一轮，看「本轮输入」是否接近上下文规模；偏差大就调 `Usage` 的合并口径。
2. **真机确认前台恢复补刷**：模拟器造不出「回后台再回前台」，`scenePhase` 与网络恢复两条路径只能在真机上看。
3. **真实数据下的渲染修整**：`ContentBlock.grouped` 每次 body 求值都重算；流式下 Markdown 每段全量重解析；thinking 块几千字展开会把正文顶出屏幕。
4. **会话管理**：重命名、搜索。
5. **真机跑一遍文件选择器**：headless 模拟器点不了 `fileImporter`，选 PDF、Word、代码文件各一次，看解析结果与计费。
6. 图片上传（`deepseek-flash` 支持图像理解，走 `image` 内容块）
7. 语音（ASR / TTS）
8. Mermaid

---

## 7. 已知限制

| 限制 | 影响 | 应对 |
|---|---|---|
| 模拟器无法横屏截图 | 横屏验证要靠 Xcode GUI | 见 BUILD_NOTES |
| 模拟器 headless | 点不了界面，交互验证靠环境变量或 UI 测试（需提权） | 尽量把状态做成可注入 |
| App 进后台被挂起 | 长回复流会被切断 | 后续用 `beginBackgroundTask` 争取约 30s |
| 用过联网工具的回复不能续写 | 「继续生成」要禁用 | 判断历史里有无工具块 |
| 单条消息的 `file_id` 历史完整保留 | 长会话上下文膨胀（文档内容每轮都计入输入） | 指标条显示剩余上下文；每轮最多 5 个文档 |
| 文档解析要等 | 大 PDF 上传 + 解析可能几十秒 | 待发卡显示上传中并禁用发送；401/402 之外失败可点卡重试 |
| 免费 Apple ID 签名 7 天过期 | 真机隔周要重签 | 长期用建议 $99 账号 |

---

## 8. 文档地图

| 文件 | 内容 |
|---|---|
| `docs/DEVELOPMENT.md` | 本文件。目标、进度、日志、下一步 |
| `docs/TECH_PLAN.md` | 技术方案：环境、选型、内容块映射、数据模型、UI 结构、里程碑 |
| `docs/BUILD_NOTES.md` | 环境坑：三个沙盒限制的解法、横屏为什么拍不到、构建命令 |
| `docs/DEVICE.md` | 上真机：签名、信任设备、免费账号 7 天续签、常见报错 |
| `docs/DESIGN.md` | 浮岛骨架的设计规范：颜色、字号、圆角、间距、组件与双端差异 |
| `Scripts/build.sh` | 编译（已内置必需的 `TMPDIR` 环境变量） |
| `Scripts/shot.sh` | 装 + 启动 + 截图 |
| `Scripts/preview-shots.sh` | 浮岛骨架的全套验收图（空态/对话/历史/余额/设置/深色 × 双端） |
| `explore/` | 四套界面方向的首屏、截图与对比页 |
| `shots/` | 各阶段截图，文件名可读 |

## 9. 协作约定

- 改动重要文件前先说明方案，等确认
- 每轮改动前备份原文件（`.build/project.pbxproj.bak` 就是这个用途）
- 代码里 `TODO(...)` 标注的是有意的欠账，带里程碑编号
- 视觉决策已定：浮岛骨架，单栏、大留白、悬浮输入。规范见 `docs/DESIGN.md`，新页面照它做，不另起一套
- **每轮有实质进展，在本文件 §5 追加一条日志，并更新文件头的「最后更新」日期**
