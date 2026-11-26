import Foundation

// MARK: - 引用

/// 正文 text 块上的 `citations`。官方在流式时通过 `citations_delta` 逐条下发。
struct Citation: Identifiable, Hashable, Sendable {
    let id = UUID()
    var url: String
    var title: String?
    var citedText: String?

    var host: String { URL(string: url)?.host ?? url }
}

// MARK: - 搜索结果

/// `web_search_tool_result` 里的单条结果。
/// `siteName` / `siteIcon` 是 DeepSeek 扩展字段，用于展示，可能为 nil。
struct SearchResult: Identifiable, Hashable, Sendable {
    let id = UUID()
    var title: String
    var url: String
    var snippet: String?
    var siteName: String?
    var siteIcon: String?
    var pageAge: String?

    var host: String { URL(string: url)?.host ?? url }
}

// MARK: - 工具调用

/// `server_tool_use` 上的 `kind` 扩展字段，标明这次调用属于哪种能力。
enum BlockKind: String, Hashable, Sendable {
    case search
    case deepSearch = "deep_search"
    case readLink = "read_link"
    case imageSearch = "image_search"
    case deepImageSearch = "deep_image_search"
}

/// `server_tool_use` 的 `input.action` 及其附带字段。
enum ToolAction: Hashable, Sendable {
    case search(queries: [String])
    case openPage(url: String)
    case findInPage(url: String, pattern: String)
    case readLink(url: String)
    case imageSearch

    var host: String? {
        switch self {
        case .openPage(let url), .readLink(let url): return URL(string: url)?.host
        case .findInPage(let url, _): return URL(string: url)?.host
        default: return nil
        }
    }
}

/// `web_fetch_tool_result` 抓到的网页。正文不返回，藏在 `signature` 里。
struct FetchedPage: Hashable, Sendable {
    var url: String
    var title: String?
    var publishedAt: String?
    /// 抓取失败时的 error_code，例如 `url_not_accessible`。
    var errorCode: String?

    var host: String { URL(string: url)?.host ?? url }
}

// MARK: - 内容块

/// 一次 assistant 回复由有序内容块组成，不是单个字符串。
/// 每个 case 都带一个稳定 id：tool_use 用服务端的 id，其余用本地生成的 id。
enum ContentBlock: Identifiable, Sendable {
    case thinking(id: String, text: String, duration: TimeInterval?)
    case toolCall(id: String, name: String, kind: BlockKind, action: ToolAction)
    case searchResults(id: String, toolUseID: String, kind: BlockKind, results: [SearchResult], errorCode: String?)
    case fetchedPage(id: String, toolUseID: String, kind: BlockKind, page: FetchedPage)
    case text(id: String, text: String, citations: [Citation])
    /// 客户端工具调用（目前只有 `remember`）。`inputJSON` 是流式拼起来的原始参数，
    /// 回传历史时必须原样送回去，所以不在这里解析成结构体。
    case toolUse(id: String, name: String, inputJSON: String)

    var id: String {
        switch self {
        case .thinking(let id, _, _): return id
        case .toolCall(let id, _, _, _): return id
        case .searchResults(let id, _, _, _, _): return id
        case .fetchedPage(let id, _, _, _): return id
        case .text(let id, _, _): return id
        case .toolUse(let id, _, _): return id
        }
    }
}

// MARK: - 渲染块

/// 渲染层视图模型。
///
/// 协议里一次搜索会下发两个块（`server_tool_use` + `web_search_tool_result`），
/// 按 `tool_use_id` 配对。直接逐个渲染会出现「搜索 2 个关键词」和结果卡片两行，
/// 官方是合成一个折叠条，所以渲染前先分组。
enum RenderBlock: Identifiable {
    case thinking(id: String, text: String, duration: TimeInterval?)
    case search(id: String, queries: [String], results: [SearchResult]?, errorCode: String?)
    case fetchedPage(id: String, page: FetchedPage)
    case text(id: String, text: String, citations: [Citation])
    /// 模型决定记一条记忆。展示成一行业务提示，不占正文位置。
    case memory(id: String, text: String)

    var id: String {
        switch self {
        case .thinking(let id, _, _): return "think-\(id)"
        case .search(let id, _, _, _): return "search-\(id)"
        case .fetchedPage(let id, _): return "fetch-\(id)"
        case .text(let id, _, _): return "text-\(id)"
        case .memory(let id, _): return "memory-\(id)"
        }
    }
}

extension ContentBlock {
    /// 按 `tool_use_id` 把工具调用与结果合组。结果的 id 与调用 id 相同时才配对成功；
    /// 服务端不保证结果紧跟在调用之后，但只在相邻位置配对已经覆盖常见情况，
    /// 远期若出现交错可以改成两遍扫描。
    static func grouped(_ blocks: [ContentBlock]) -> [RenderBlock] {
        var output: [RenderBlock] = []
        var index = 0

        while index < blocks.count {
            let block = blocks[index]

            switch block {
            case .thinking(let id, let text, let duration):
                output.append(.thinking(id: id, text: text, duration: duration))
                index += 1

            case .toolCall(let id, _, _, .search(let queries)):
                var results: [SearchResult]?
                var errorCode: String?
                var consumed = 1

                if index + 1 < blocks.count,
                   case .searchResults(_, let toolUseID, _, let found, let error) = blocks[index + 1],
                   toolUseID == id {
                    results = found
                    errorCode = error
                    consumed = 2
                }

                output.append(.search(id: id, queries: queries, results: results, errorCode: errorCode))
                index += consumed

            case .toolCall(_, _, _, _):
                // open_page / find_in_page / read_link 的展示由后面的 fetchedPage 块承担
                index += 1

            case .searchResults(_, let toolUseID, _, let results, let errorCode):
                output.append(.search(id: toolUseID, queries: [], results: results, errorCode: errorCode))
                index += 1

            case .fetchedPage(let id, _, _, let page):
                output.append(.fetchedPage(id: id, page: page))
                index += 1

            case .text(let id, let text, let citations):
                output.append(.text(id: id, text: text, citations: citations))
                index += 1

            case .toolUse(let id, _, let inputJSON):
                // 认不出的客户端工具直接不展示，但块本身仍在，回传历史不受影响
                if let text = Self.memoryText(from: inputJSON) {
                    output.append(.memory(id: id, text: text))
                }
                index += 1
            }
        }
        return output
    }

    /// 从 `remember` 的参数里取要展示的那句话。
    static func memoryText(from inputJSON: String) -> String? {
        guard let data = inputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? String else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
