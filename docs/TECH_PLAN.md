# iPad-DS 技术方案（立项稿）

> ⚠️ **这份是 2026-11-24 立项时写的方案，实现已经大幅偏离**：工程改用 XcodeGen 之外的方案、界面换成浮岛骨架、协议与内容块映射也有调整。
> **现状一律以 [DEVELOPMENT.md](DEVELOPMENT.md) 为准**，这里只留作「当初怎么想的」参考。

> 目标：用 Swift 原生写一个 iPhone/iPad 通用的 DeepSeek 客户端，通过官方 API 复现官方 App 的对话体验。
> 范围：自用。API Key 存本机 Keychain，客户端直连 `api.deepseek.com`，不做后端。
> 文档版本：v1 · 2026-11-24
>
> **实现进度（2026-11-24）**：界面层已完成并可编译运行——双端布局、内容块渲染器（思考折叠、搜索调用与结果合并条、引用角标、表格、代码语法高亮）、浅色与深色、输入条开关。数据仍是样例。真实 API 接入、SwiftData 持久化、语音、Mermaid 未开始。截图在 `shots/`，环境坑记录在 `docs/BUILD_NOTES.md`。

---

## 1. 环境实况

实测于本机，写方案时的事实基线：

| 项目 | 值 | 结论 |
|---|---|---|
| macOS | 27.2.1 / arm64 | 支持 |
| 可用磁盘 | 618 GB | 够（Xcode + 模拟器约 60–70 GB） |
| Swift 编译器 | 6.4.2（Command Line Tools） | 够写代码，不够建 iOS 工程 |
| Xcode.app | **未安装** | 阻塞项，需人工装 |
| iOS SDK / 模拟器 / `simctl` / `xcodebuild` | **缺失** | 同上 |
| 代码签名身份 | 0 个 | 真机调试前需 Apple ID 登录一次 |
| VS Code | 已装 | 加 Swift 扩展即可读码 |
| 工作目录 | `~/Desktop/iPad-DS`（空） | 从零开始 |

装完 Xcode 后把 `xcode-select` 指向它：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version        # 验证
xcrun simctl list devices  # 验证模拟器可用
```

---

## 2. 技术选型

| 决策项 | 选择 | 理由 |
|---|---|---|
| UI 框架 | **SwiftUI**，纯代码 | iPhone/iPad 自适应靠 `horizontalSizeClass` 分支，不需要 Storyboard；可全文本编辑，VS Code 读改无压力 |
| 最低部署目标 | **iOS 18.0** | SwiftData、`NavigationSplitView`、`URLSession.bytes` 全可用；覆盖面最广。若你的 iPhone/iPad 都 ≥26 可提到 26.0 换取系统新材质 |
| 接口协议 | **Anthropic Messages 格式** `POST /anthropic/v1/messages` | 内容块结构与 UI 渲染需求一一对应；思考、联网、引用、会话标题、安全审核都是一等参数。详见 §3.1 对比 |
| 流式 | `URLSession.bytes(for:)` + 手写 SSE 解析 | 零依赖，约 120 行。`AsyncThrowingStream` 向上抛事件 |
| 持久化 | **SwiftData** | 系统内置，无第三方；本文档用"原始 JSON 块"策略规避 schema 迁移风险（见 §5） |
| Markdown | `apple/swift-markdown` 解析 + 自写渲染 | 官方 CommonMark 实现，只做解析不做 UI；渲染层自己控制，才能做出代码块复制、表格、横向滚动 |
| Mermaid | `WKWebView` 内联本地 mermaid.min.js | 沙盒离线可用，避免 CDN 依赖 |
| 依赖数量 | 1 个 SPM 包 | 自用项目，可控性优先 |
| 工程文件 | **XcodeGen**（`project.yml`） | `.pbxproj` 是二进制语义的文本，手改易冲突；用 YAML 描述后重新生成 |
| 密钥存储 | Keychain（`kSecClassGenericPassword`） | 系统加密，不进 UserDefaults，不进 Git |

### 2.1 协议对比（决定因素）

| | Messages | Chat Completions | Responses |
|---|---|---|---|
| 内容块原生支持 | 完整，块结构最贴近 UI | 有，字段名不同 | 有 |
| 继续生成 | 消息列表末尾放未完成 assistant 即可 | 需 beta 接口 + `prefix: true` | 不支持 |
| 会话标题 | `title: {enabled: true}`，随 `message_delta` 返回 | 需单独说明 | 同样支持 |
| 多轮回传块 | 原样回传，含 `kind`/`signature` | 需转换 | 需转换 |
| 官方示例覆盖度 | 全部示例主用它 | 部分 | 部分 |

选 Messages 的直接原因：官方把最完整的功能示例都写在这个格式上，字段名语义清晰，调试时对着文档能一一对上。

---

## 3. 架构

### 3.1 分层

```
┌──────────────────────────────────────────────┐
│  Views (SwiftUI)                             │
│  ChatView · ConversationList · Composer       │
└─────────────────┬────────────────────────────┘
                  │ @Observable 状态
┌─────────────────▼────────────────────────────┐
│  ChatViewModel                                │
│  接收 StreamEvent，维护 blocks 数组            │
└─────────────────┬────────────────────────────┘
                  │ AsyncThrowingStream<StreamEvent>
┌─────────────────▼────────────────────────────┐
│  ChatStream / APIClient                       │
│  URLSession.bytes → SSEParser → StreamEvent   │
└─────────────────┬────────────────────────────┘
                  │
┌─────────────────▼────────────────────────────┐
│  Store (SwiftData) + KeychainStore            │
│  blocksJSON 权威存储 · 原样回传                 │
└──────────────────────────────────────────────┘
```

### 3.2 内容块模型（核心）

服务端一次回复是一串有序块，不是一个字符串。照官方文档映射：

| 协议块 | 出现的场景 | UI 呈现 |
|---|---|---|
| `thinking` | 思考模式，可能空块 | 可折叠的"思考中…"，流式逐字 |
| `server_tool_use`（`action: search`，`kind: search`） | 联网搜索 | "正在搜索 N 个关键词"折叠条 |
| `server_tool_use`（`action: open_page` / `find_in_page`，`kind: deep_search`） | 深度思考搜索 | 步骤条，显示打开的 URL / 查找的词 |
| `server_tool_use`（`action: read_link`，`kind: read_link`） | 阅读用户给的链接 | "正在阅读：域名" |
| `web_search_tool_result` | 搜索结果 | 卡片：标题 + 站点名 + 站点图标 + 摘要，可展开 |
| `web_fetch_tool_result` | 打开的网页 | 卡片：标题 + 域名 + 日期；正文为空，靠 `signature` 还原 |
| `text`（带 `citations`） | 正文含引用 | Markdown + 行内引用角标 `[1]`，点击弹出来源 |
| `text`（无引用） | 普通正文 | Markdown |

Swift 侧对应：

```swift
enum ContentBlock: Sendable {
    case thinking(text: String, signature: String?)
    case serverToolUse(id: String, name: String, action: String, kind: BlockKind, input: ToolInput)
    case webSearchResult(toolUseID: String, kind: BlockKind, results: [SearchResult], error: String?)
    case webFetchResult(toolUseID: String, kind: BlockKind, fetch: FetchResult?, signature: String?)
    case text(text: String, citations: [Citation])
    /// 兜底：任何未识别的新块类型都保留原始 JSON
    case unknown(type: String, rawJSON: Data)
}
```

**每个块都同时保留 `rawJSON`。** 这是整个方案里最关键的一条约束，理由见 §5.1。

### 3.3 SSE 事件处理

官方流式事件顺序（开启思考 + 一次搜索）：

```
message_start
content_block_start(thinking) → thinking_delta … → signature_delta → content_block_stop
content_block_start(server_tool_use) → content_block_stop
content_block_start(web_search_tool_result) → content_block_stop
content_block_start(thinking) → … → content_block_stop
content_block_start(text) → text_delta … → citations_delta … → content_block_stop
message_delta
message_stop
```

要点：

1. **块内容可能在同一 index 上多次打开**（思考 → 搜索 → 再思考），用 `index` 定位，不能假设"最后一个块就是当前块"。
2. `server_tool_use` 和结果块的内容**一次性出现在 `content_block_start` 里**，不会分片下发，无需增量拼接。
3. 结果块与调用块按 `tool_use_id` 关联，**不保证紧邻**（多链接并发、开启安全审核时）。UI 层要把结果挂到对应调用上，不能按出现顺序配对。
4. 空的 `thinking` 块会出现（模型先搜索再思考），渲染层要能处理空块。
5. 流中可能有 `: keep-alive` 注释行，忽略。
6. 出错时 HTTP 仍是 200，流尾部是 `error` 事件且**没有** `message_delta`/`message_stop`。解析器必须能识别这种"正常结束之外"的终止。
7. `usage` 以最终 `message_delta` 为准，`message_start` 里的只是第一步。

初始版本先不做搜索，把 1/2/5/6 打通；联网进里程碑 3。

### 3.4 请求构造

```http
POST https://api.deepseek.com/anthropic/v1/messages
content-type: application/json
x-api-key: <Keychain 取出>
```

```json
{
  "model": "deepseek-flash",
  "thinking": { "type": "enabled" },
  "title": { "enabled": true },
  "tools": [
    { "type": "deepseek_web_search", "name": "deepseek_web_search" },
    { "type": "deepseek_read_url", "name": "deepseek_read_url" }
  ],
  "messages": [ … ],
  "stream": true
}
```

`tools` 与 `title` 按用户在设置里的开关动态拼装。**不传 `temperature`**：声明联网工具或开启 `safety_check: high` 时，服务端会忽略 `temperature`/`top_p`/`stop` 等参数。如果做"创造性/严谨"滑杆，只在纯对话模式下发。

待验证：Anthropic 兼容接口是否强制要求 `anthropic-version` 头。里程碑 0 第一次实调用时确认，缺了会报错，加上即可，不影响架构。

---

## 4. UI 结构

### 4.1 双端布局

```swift
@Environment(\.horizontalSizeClass) var hSize

if hSize == .regular {
    NavigationSplitView { ConversationSidebar() } detail: { ChatView() }
} else {
    NavigationStack { ChatListOrChat() }   // 会话列表 → 推入对话
}
```

| 设备 | 布局 | 细节 |
|---|---|---|
| iPhone 竖屏 | 单列，`NavigationStack` | 键盘顶起输入框，自动滚到底 |
| iPhone 横屏 / iPad 分屏窄栏 | compact → 单列 | 与竖屏同逻辑 |
| iPad 全屏 | 左侧 320pt 会话栏 + 右侧对话 | 可拖拽调宽，`.navigationSplitViewColumnWidth` |
| iPad 横屏大空间 | 可选：内容最大宽度限制 760pt 居中 | 超长行宽伤可读性 |

### 4.2 对话页组成

- **消息列表**：`ScrollView` + `LazyVStack`，不用 `List`（流式频繁更新时 List 会闪）。流式中用 `scrollPosition` 跟随，用户手动上滑则停止跟随。
- **内容块渲染**：`ForEach(blocks)` + `switch`。未知块渲染为空，不崩。
- **输入条**：多行自适应 `TextField(axis: .vertical)`，高度 1–6 行。附件按钮（图片/文件）、联网开关、思考开关。
- **停止按钮**：流式中替换发送键，取消 `Task`，保留已收到的块并标记为 `stopped`。
- **复制/重生成**：长按消息或工具栏菜单。

### 4.3 空态与错误态

必须有明确文案的场景：无 Key、Key 无效（401）、余额不足（402）、限流（429）、上下文超长（400）、审核拒答（`stop_reason: refusal`）、网络断开。每个都要有具体的下一步动作提示，不能只显示"出错了"。

---

## 5. 数据模型

### 5.1 关键设计：存原始 JSON 块

```swift
@Model final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var model: String
    @Relationship(deleteRule: .cascade) var messages: [Message]
}

@Model final class Message {
    var id: UUID
    var roleRaw: String            // user / assistant
    var blocksJSON: String         // ★ 权威数据：块数组的原始 JSON
    var plainText: String          // 提取的纯文本，供列表预览与搜索
    var attachmentsJSON: String?   // 用户消息：图片 base64 / file_id
    var statusRaw: String          // streaming / complete / stopped / failed / refused
    var usageJSON: String?
    var createdAt: Date
}
```

为什么存原始 JSON 而不用 SwiftData 关系建模每个块：

官方明确要求多轮对话**把之前每一轮的回复原样回传，保留 `kind` 和 `signature`**。`read_link` 的网页正文就藏在 `signature` 里，丢了之后该网页在后续轮次就消失，模型会答"我不知道你指的是哪个网页"。结构化建模会在字段演进时静默丢字段，用户不会察觉，只会在某天发现"它怎么不记得刚才那个链接"。

存原始 JSON 的三个收益：
1. 回传时可直接拼回请求体，`signature`/`encrypted_content`/未来新字段全保留。
2. API 加新块类型时，App 不需要迁移数据库；渲染层不认识的块渲染为空，但数据完整。
3. 模型结构变化只需改解码器，`blocksJSON` 不动。

代价：块级字段查不了。自用场景不需要。

### 5.2 回传构造

```swift
func toWireMessages(_ history: [Message]) -> [[String: Any]] {
    history.map { msg in
        // blocksJSON 直接解回 [Any]，不做 Swift 模型往返
        ["role": msg.role, "content": try! JSONSerialization.jsonObject(with: msg.blocksJSON.data(using: .utf8)!)]
    }
}
```

用户消息也要包成块数组（`{"type":"text","text":"…"}`），保持格式一致。

### 5.3 附件

- 图片：压到长边 1568px、JPEG 0.85，base64 内联进 `image` 块。单张控制在 1 MB 内，避免请求体过大。
- 文档（PDF/DOCX/PPTX）：先 `POST /files` 拿 `file_id`，再在消息里用 `document` 块引用。上传接口同步返回，解析可能耗时数十秒，需要 loading 并放宽超时（上传 120s + 解析 120s）。
- 注意 `purpose` 字段必须**放在 `file` 字段之前**，否则 400。
- 纯文本/表格/电子书用 `purpose: user_data`，不计费。

### 5.4 会话标题

用 `title: {enabled: true}`，标题随 `message_delta` 一并返回，无需额外请求。首轮结束后写入 `Conversation.title`；用户手动改名后置一个 `titleIsManual` 标记，避免被后续自动标题覆盖。

---

## 6. Markdown 与富内容

`Text(AttributedString(markdown:))` 只覆盖行内样式，代码块、表格、列表缩进都会退化。所以分层做：

| 元素 | 实现 |
|---|---|
| 段落 / 行内格式 / 链接 | `swift-markdown` 解析成 AST，自己递归渲染 |
| 代码块 | 等宽字体 + 横向滚动 + 语言标签 + 复制按钮；轻量关键字高亮（Swift/JS/Python/JSON 四套正则即可） |
| 表格 | `Grid`，列宽按内容分配，超宽横向滚动 |
| 列表（含嵌套） | 缩进 + 自定义 bullet |
| 引用块和分割线 | 左侧竖线 / `Divider` |
| Mermaid | `WKWebView` + 本地 `mermaid.min.js`，高度由 JS 回传 |
| 行内引用角标 | `citations` 映射为 `[1][2]`，点击弹 sheet 显示来源标题+URL+摘录 |

流式渲染的性能约束：每个 `text_delta` 都触发重新解析会卡。做法是**节流到 ~60ms 一次，且只重新解析最后一块**，已完成块用缓存 AST。

---

## 7. 工程结构

```
iPad-DS/
├── project.yml                  # XcodeGen
├── docs/TECH_PLAN.md
├── Scripts/
│   ├── bootstrap.sh             # 生成工程、装 Swift 扩展提示
│   ├── build.sh                 # xcodebuild 编译（双端）
│   └── shot.sh                  # 模拟器启动+截图
├── Sources/
│   ├── App/DSApp.swift, RootView.swift
│   ├── Core/
│   │   ├── Network/APIClient.swift, SSEParser.swift, ChatStream.swift
│   │   ├── Models/ContentBlock.swift, StreamEvent.swift, WireMessage.swift
│   │   ├── Storage/Store.swift, KeychainStore.swift
│   │   └── Settings/AppSettings.swift
│   ├── Features/
│   │   ├── Chat/ChatView.swift, ChatViewModel.swift, MessageRow.swift, Composer.swift
│   │   ├── Conversations/ConversationList.swift
│   │   └── Settings/SettingsView.swift
│   ├── UI/
│   │   ├── Blocks/  ThinkingView, ToolCallRow, SearchResultCard, CitationChip
│   │   ├── Markdown/ MarkdownView, CodeBlock, TableView, MermaidView
│   │   └── Theme/
│   └── Resources/ Assets.xcassets, mermaid.min.js
└── Tests/
    ├── SSEParserTests.swift
    ├── ContentBlockTests.swift
    └── WireRoundTripTests.swift   # 原样回传的往返一致性
```

`project.yml` 要点：

```yaml
name: iPadDS
options:
  bundleIdPrefix: com.ruakiu
  deploymentTarget:
    iOS: "18.0"
targets:
  iPadDS:
    type: application
    platform: iOS
    sources: [Sources]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ruakiu.ipadds
        TARGETED_DEVICE_FAMILY: "1,2"     # iPhone + iPad
        SWIFT_VERSION: "6.0"
        ENABLE_USER_SCRIPT_SANDBOXING: NO
    dependencies:
      - package: swift-markdown
  iPadDSTests:
    type: bundle.unit-test
    dependencies: [{ target: iPadDS }]
```

---

## 8. 里程碑

### 里程碑 0 · 骨架跑通（半天）
- XcodeGen 生成工程，双端模拟器能装能启动
- Settings 页存 Key 进 Keychain，重启后仍在
- 纯文本流式对话：发一句，文字逐字出现
- 401 / 断网有明确错误提示
- **验收**：iPhone 16 Pro 与 iPad Pro 13" 模拟器各截一张图，都能对话

### 里程碑 1 · 双端适配 + 持久化（1–2 天）
- `NavigationSplitView` / `NavigationStack` 双布局
- SwiftData 存会话与消息，冷启动能读回
- 会话列表、新建、删除、重命名
- 深色模式、动态字体
- **验收**：iPhone 竖横屏 + iPad 全屏/分屏四种状态截图无布局破相

### 里程碑 2 · 富内容渲染（2–3 天，最大块）
- 内容块渲染器全量：思考折叠、工具调用行、结果卡片、引用角标
- Markdown 完整渲染 + 代码高亮 + 复制
- 流式性能优化（节流 + AST 缓存）
- **验收**：一次 3000 字带代码块的回复，流式过程不掉帧、不发散

### 里程碑 3 · 联网与文件（1–2 天）
- `deepseek_web_search` / `deepseek_read_url` 开关
- 搜索卡片、结果展开
- 图片上传、PDF 上传（`/files` + `file_id`）
- **验收**：问一个需要搜索的问题，能看到搜索卡片和正文引用角标

### 里程碑 4 · 语音与打磨（1–2 天）
- ASR 语音输入、TTS 朗读回答
- 用量与费用显示
- 真机签名调试

---

## 9. 已知限制

| 限制 | 影响 | 应对 |
|---|---|---|
| App 进后台被挂起 | 长回复流会被切断 | 申请 `beginBackgroundTask` 争取约 30s；超出后标记"已中断"，可续写 |
| 使用过联网工具的回复不能续写 | "继续生成"按钮需禁用 | 判断历史里有无工具块，动态隐藏 |
| 单条消息里 `file_id` 历史会完整保留 | 长会话上下文膨胀 | 显示 token 占用，提示新建会话 |
| 开启联网/安全审核后参数被忽略 | 温度滑杆失效 | UI 上置灰并说明 |
| 免费 Apple ID 签名 7 天过期 | 真机隔周要重签 | 真机长期用建议 $99 账号，或每次重签 |
| 自用无后端 | Key 在设备上，设备丢失即泄露 | 可随时去平台后台重置 Key |

---

## 10. 待确认

动手前需要你给三个信息：

1. **设备**：iPad 型号、iPhone 型号、各自 iOS 版本。这决定部署目标设 18.0 还是 26.0。
2. **API Key**：是否已在 `platform.deepseek.com` 创建。里程碑 0 需要一次真实调用验证。
3. **模型默认值**：默认 `deepseek-flash`（便宜、支持图像理解）还是 `deepseek-v4-pro`（更贵更强，不支持图像）。我倾向 flash 作默认、可在设置里切。

我在拿到这三个答复后，按里程碑 0 开工：先出 `project.yml` + 网络层 + Keychain，你在 Xcode 装好后一条命令编译。
