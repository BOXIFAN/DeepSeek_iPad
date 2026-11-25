import SwiftUI

/// 界面方向探索入口。
///
/// 启动时带 `DS_UI_VARIANT=paper|floating|desk|cards` 环境变量，
/// 渲染对应方向的静态首屏，用于同机位对比截图。
/// 不带变量时走正式的 `RootView`，不影响日常使用。
struct ExploreRoot: View {
    var body: some View {
        if let raw = ProcessInfo.processInfo.environment["DS_UI_VARIANT"],
           let variant = UIVariant(rawValue: raw) {
            switch variant {
            case .paper: PaperRoot()
            case .floating: FloatingRoot()
            case .desk: DeskRoot()
            case .cards: CardsRoot()
            }
        } else {
            RootView()
        }
    }
}

enum UIVariant: String {
    case paper
    case floating
    case desk
    case cards
}

// MARK: - 演示数据

/// 四个方向共用同一份对话内容，差异只体现在骨架与视觉上。
enum ExploreDemo {
    struct Conversation: Identifiable {
        let id = UUID()
        var title: String
        var preview: String
        var time: String
        var model: String
        var tokens: String
    }

    static let conversations: [Conversation] = [
        .init(title: "DeepSeek 模型能力与价格",
              preview: "现在的主力是两个模型，deepseek-flash…",
              time: "4:01",
              model: "flash",
              tokens: "12.4k"),
        .init(title: "Swift 并发里的 actor 隔离",
              preview: "在 Swift 6 严格并发模式下，MainActor…",
              time: "昨天",
              model: "v4-pro",
              tokens: "8.1k"),
        .init(title: "把长文档拆成章节再总结",
              preview: "先按一级标题切分，每段单独总结，最后…",
              time: "昨天",
              model: "flash",
              tokens: "31.7k"),
        .init(title: "SQLite 索引选择",
              preview: "复合索引的列顺序决定了能命中哪些查询…",
              time: "周一",
              model: "flash",
              tokens: "5.2k"),
        .init(title: "Keychain 存 API Key 的几种做法",
              preview: "kSecAttrAccessibleAfterFirstUnlock…",
              time: "上周",
              model: "v4-pro",
              tokens: "2.9k"),
    ]

    static let conversationTitle = "DeepSeek 模型能力与价格"

    static let messages: [ChatViewModel.DisplayMessage] = [
        .init(id: "u1", role: .user, text: SampleData.userQuestion, blocks: []),
        .init(id: "a1", role: .assistant, text: "", blocks: SampleData.assistantBlocks),
        .init(id: "u2",
              role: .user,
              text: "按每天 200 万 tokens、其中一半命中缓存估算，一个月大概多少钱？",
              blocks: []),
        .init(id: "a2",
              role: .assistant,
              text: "",
              blocks: [
                .text(
                    id: "blk-follow-up",
                    text: """
                    按每天 200 万 tokens 拆：输入 140 万、输出 60 万，输入里一半命中缓存。空闲时段单价是缓存命中 0.02 元、未命中 1 元、输出 4 元，单位都是每百万 tokens。

                    | 项目 | 用量 | 单价 | 小计 |
                    | --- | --- | --- | --- |
                    | 命中输入 | 70 万 | 0.02 元 | 0.014 元 |
                    | 未命中输入 | 70 万 | 1 元 | 0.7 元 |
                    | 输出 | 60 万 | 4 元 | 2.4 元 |

                    每天约 3.11 元，一个月（30 天）约 93 元。如果全在高峰时段跑，翻一倍到 186 元上下。
                    """,
                    citations: []
                )
              ])
    ]

    /// 单独取第一轮问答，给只展示一轮的方向用。
    static var firstRound: [ChatViewModel.DisplayMessage] {
        Array(messages.prefix(2))
    }

    static let sources: [(String, String, String)] = [
        ("模型 & 价格", "api-docs.deepseek.com", "2026-11-13"),
        ("DeepSeek 开放平台文档", "api-docs.deepseek.com", "2026-11-20"),
        ("构建 Chatbot — 联网搜索与文件输入", "api-docs.deepseek.com", "2026-11-18"),
    ]

    static let keyNumbers: [(String, String)] = [
        ("上下文", "1M"),
        ("输出上限", "384K"),
        ("缓存命中输入", "0.02 元"),
        ("缓存未命中输入", "1 元"),
    ]
}

// MARK: - 共用小件

/// 助手消息的内容块渲染。各方向只是外面套的容器不同。
struct DemoAssistantBody: View {
    let blocks: [ContentBlock]
    var serif: Bool = false
    var bodySize: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ContentBlock.grouped(blocks)) { block in
                switch block {
                case .thinking(_, let text, let duration):
                    DemoThinkingLine(text: text, duration: duration, serif: serif)
                case .search(_, let queries, let results, _):
                    DemoSearchLine(queries: queries, results: results ?? [])
                case .fetchedPage(_, let page):
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                        Text(page.title ?? page.host)
                            .font(.footnote)
                        Text("· \(page.host)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                case .text(_, let text, let citations):
                    MarkdownView(
                        text: text,
                        citations: citations,
                        serif: serif,
                        bodySize: bodySize,
                        surface: serif ? PaperInk.card : nil
                    )
                }
            }
        }
    }
}

struct DemoThinkingLine: View {
    let text: String
    let duration: TimeInterval?
    var serif: Bool = false

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 5, height: 5)
                    Text(title)
                        .font(serif ? .system(.footnote, design: .serif) : .footnote)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(serif ? .system(.footnote, design: .serif) : .footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1.5)
                    }
            }
        }
    }

    private var title: String {
        if let duration { return "已深度思考 · \(Int(duration)) 秒" }
        return "深度思考"
    }
}

struct DemoSearchLine: View {
    let queries: [String]
    let results: [SearchResult]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
            Text("检索 \(queries.count) 个关键词 · \(results.count) 个来源")
                .font(.footnote)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(.secondary)
    }
}
