import Foundation

extension ContentBlock {

    /// 从协议块 JSON 重建模型。
    ///
    /// 流式解码和历史加载走同一套逻辑，避免两边字段解释不一致。
    /// `fallbackID` 在块里没有 `id` 时使用（thinking / text 这类块本来就没有）。
    static func make(from raw: [String: Any], id fallbackID: String) -> ContentBlock? {
        switch raw["type"] as? String ?? "" {

        case "thinking":
            return .thinking(id: fallbackID,
                             text: raw["thinking"] as? String ?? "",
                             duration: nil)

        case "text":
            return .text(id: fallbackID,
                         text: raw["text"] as? String ?? "",
                         citations: citations(from: raw["citations"]))

        case "server_tool_use":
            guard let input = raw["input"] as? [String: Any],
                  let action = action(from: input) else { return nil }
            let kind = BlockKind(rawValue: raw["kind"] as? String ?? "") ?? .search
            return .toolCall(id: raw["id"] as? String ?? fallbackID,
                             name: raw["name"] as? String ?? "",
                             kind: kind,
                             action: action)

        case "web_search_tool_result":
            let items = raw["content"] as? [[String: Any]] ?? []
            var errorCode: String?
            if let first = items.first, first["type"] as? String == "web_search_tool_result_error" {
                errorCode = first["error_code"] as? String
            }
            let results = items.compactMap { item -> SearchResult? in
                guard item["type"] as? String == "web_search_result" else { return nil }
                return SearchResult(
                    title: item["title"] as? String ?? "",
                    url: item["url"] as? String ?? "",
                    snippet: item["snippet"] as? String,
                    siteName: item["site_name"] as? String,
                    siteIcon: item["site_icon"] as? String,
                    pageAge: item["page_age"] as? String
                )
            }
            let kind = BlockKind(rawValue: raw["kind"] as? String ?? "") ?? .search
            return .searchResults(id: fallbackID,
                                  toolUseID: raw["tool_use_id"] as? String ?? fallbackID,
                                  kind: kind,
                                  results: results,
                                  errorCode: errorCode)

        case "web_fetch_tool_result":
            let content = raw["content"] as? [String: Any]
            var page = FetchedPage(url: "", title: nil, publishedAt: nil, errorCode: nil)
            if (content?["type"] as? String) == "web_fetch_tool_result_error" {
                page.errorCode = content?["error_code"] as? String
            } else {
                page.url = content?["url"] as? String ?? ""
                page.publishedAt = content?["published_at"] as? String
                if let document = content?["content"] as? [String: Any] {
                    page.title = document["title"] as? String
                }
            }
            let kind = BlockKind(rawValue: raw["kind"] as? String ?? "") ?? .readLink
            return .fetchedPage(id: fallbackID,
                                toolUseID: raw["tool_use_id"] as? String ?? fallbackID,
                                kind: kind,
                                page: page)

        default:
            return nil
        }
    }

    /// 把已存储的一轮助手块数组还原成内容块。
    static func decodeAll(_ rawBlocks: [[String: Any]]) -> [ContentBlock] {
        rawBlocks.enumerated().compactMap { index, raw in
            make(from: raw, id: raw["id"] as? String ?? "历史-\(index)-\(UUID().uuidString.prefix(6))")
        }
    }

    private static func citations(from raw: Any?) -> [Citation] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.map {
            Citation(url: $0["url"] as? String ?? "",
                     title: $0["title"] as? String,
                     citedText: $0["cited_text"] as? String)
        }
    }

    private static func action(from input: [String: Any]) -> ToolAction? {
        switch input["action"] as? String {
        case "search":
            return .search(queries: input["queries"] as? [String] ?? [])
        case "open_page":
            return .openPage(url: input["url"] as? String ?? "")
        case "find_in_page":
            return .findInPage(url: input["url"] as? String ?? "",
                               pattern: input["pattern"] as? String ?? "")
        case "read_link":
            return .readLink(url: input["url"] as? String ?? "")
        default:
            return nil
        }
    }
}
