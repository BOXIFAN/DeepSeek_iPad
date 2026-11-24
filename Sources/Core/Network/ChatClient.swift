import Foundation

// MARK: - 用量

struct Usage: Sendable, Equatable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var thinkingTokens = 0

    static func from(_ dict: [String: Any]?) -> Usage? {
        guard let dict else { return nil }
        var usage = Usage()
        usage.inputTokens = dict["input_tokens"] as? Int ?? 0
        usage.outputTokens = dict["output_tokens"] as? Int ?? 0
        usage.cacheReadTokens = dict["cache_read_input_tokens"] as? Int ?? 0
        if let details = dict["output_tokens_details"] as? [String: Any] {
            usage.thinkingTokens = details["thinking_tokens"] as? Int ?? 0
        }
        return usage
    }
}

// MARK: - 增量

enum BlockDelta: Sendable {
    case thinking(String)
    case signature(String)
    case text(String)
    case citation(Citation)
}

// MARK: - 流事件

/// 一次流式响应被拆成的事件序列。顺序与官方文档一致：
/// message_start → (blockStart → delta… → blockStop)* → message_delta → message_stop
enum StreamEvent: Sendable {
    case messageStart
    case blockStart(index: Int, block: ContentBlock)
    case blockDelta(index: Int, delta: BlockDelta)
    case blockStop(index: Int)
    case messageDelta(stopReason: String?, title: String?, usage: Usage?)
    case messageStop
    /// 流内错误事件：HTTP 已经是 200，但生成中途失败。
    case failure(String)
}

// MARK: - 错误

enum ChatError: LocalizedError {
    case badResponse
    case http(Int, String)
    case format(String)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "服务器返回了无法识别的响应"
        case .http(let code, let detail):
            switch code {
            case 401:
                return "API Key 无效或已失效，请到设置里重新填写"
            case 402:
                return "账户余额不足，请到 DeepSeek 开放平台充值"
            case 429:
                return "请求过于频繁，等几秒再试"
            case 400:
                return detail.isEmpty ? "请求参数有误" : detail
            case 413:
                return "上传的内容太大"
            case 500, 502, 503, 504:
                return "服务端暂时不可用，稍后再试"
            default:
                return detail.isEmpty ? "请求失败（HTTP \(code)）" : "HTTP \(code)：\(detail)"
            }
        case .format(let message):
            return "响应格式异常：\(message)"
        case .serverMessage(let message):
            return message
        }
    }
}

// MARK: - 客户端

/// 直连 DeepSeek 的 Anthropic 兼容接口，走 SSE 流式。
final class ChatClient {

    private let endpoint = URL(string: "https://api.deepseek.com/anthropic/v1/messages")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // 首字节可能要等推理，给长一点；整条流的上限再放宽
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    struct Options {
        var model = "deepseek-flash"
        var thinking = true
        var webSearch = false
        var generateTitle = false
        var maxTokens = 8192
    }

    /// - Parameter messages: 已经组装好的协议消息数组，`content` 保持原始块结构。
    func stream(apiKey: String,
                messages: [[String: Any]],
                options: Options) -> AsyncThrowingStream<StreamEvent, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: Any] = [
                        "model": options.model,
                        "stream": true,
                        "max_tokens": options.maxTokens,
                        "messages": messages
                    ]
                    if options.thinking {
                        body["thinking"] = ["type": "enabled"]
                    }
                    if options.generateTitle {
                        body["title"] = ["enabled": true]
                    }
                    if options.webSearch {
                        body["tools"] = [
                            ["type": "deepseek_web_search", "name": "deepseek_web_search"],
                            ["type": "deepseek_read_url", "name": "deepseek_read_url"]
                        ]
                    }

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ChatError.badResponse
                    }

                    guard (200..<300).contains(http.statusCode) else {
                        var text = ""
                        for try await line in bytes.lines { text += line }
                        throw ChatError.http(http.statusCode, Self.extractMessage(from: text))
                    }

                    var parser = SSEParser()
                    for try await rawLine in bytes.lines {
                        if Task.isCancelled { break }
                        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                        guard let sse = parser.consume(line) else { continue }
                        for event in Self.decode(sse) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 事件解码

    private static func decode(_ sse: SSEEvent) -> [StreamEvent] {
        guard let data = sse.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let type = json["type"] as? String ?? sse.name

        switch type {
        case "message_start":
            return [.messageStart]

        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let raw = json["content_block"] as? [String: Any],
                  let block = makeBlock(raw, index: index) else {
                return []
            }
            return [.blockStart(index: index, block: block)]

        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any] else {
                return []
            }
            if let parsed = makeDelta(delta) {
                return [.blockDelta(index: index, delta: parsed)]
            }
            return []

        case "content_block_stop":
            guard let index = json["index"] as? Int else { return [] }
            return [.blockStop(index: index)]

        case "message_delta":
            let delta = json["delta"] as? [String: Any]
            return [.messageDelta(
                stopReason: delta?["stop_reason"] as? String,
                title: delta?["title"] as? String,
                usage: Usage.from(json["usage"] as? [String: Any])
            )]

        case "message_stop":
            return [.messageStop]

        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String
                ?? "生成中断，请重试"
            return [.failure(message)]

        default:
            return []
        }
    }

    private static func makeDelta(_ delta: [String: Any]) -> BlockDelta? {
        switch delta["type"] as? String {
        case "thinking_delta":
            return .thinking(delta["thinking"] as? String ?? "")
        case "signature_delta":
            return .signature(delta["signature"] as? String ?? "")
        case "text_delta":
            return .text(delta["text"] as? String ?? "")
        case "citations_delta":
            guard let raw = delta["citation"] as? [String: Any] else { return nil }
            return .citation(Citation(
                url: raw["url"] as? String ?? "",
                title: raw["title"] as? String,
                citedText: raw["cited_text"] as? String
            ))
        default:
            return nil
        }
    }

    private static func makeBlock(_ raw: [String: Any], index: Int) -> ContentBlock? {
        let id = "stream-\(index)"
        let type = raw["type"] as? String ?? ""

        switch type {
        case "thinking":
            return .thinking(id: id,
                             text: raw["thinking"] as? String ?? "",
                             duration: nil)

        case "text":
            return .text(id: id,
                         text: raw["text"] as? String ?? "",
                         citations: parseCitations(raw["citations"]))

        case "server_tool_use":
            guard let input = raw["input"] as? [String: Any],
                  let action = parseAction(input) else { return nil }
            let kind = BlockKind(rawValue: raw["kind"] as? String ?? "") ?? .search
            return .toolCall(id: raw["id"] as? String ?? id,
                             name: raw["name"] as? String ?? "",
                             kind: kind,
                             action: action)

        case "web_search_tool_result":
            let results = (raw["content"] as? [[String: Any]])?.compactMap { item -> SearchResult? in
                guard (item["type"] as? String) == "web_search_result" else { return nil }
                return SearchResult(
                    title: item["title"] as? String ?? "",
                    url: item["url"] as? String ?? "",
                    snippet: item["snippet"] as? String,
                    siteName: item["site_name"] as? String,
                    siteIcon: item["site_icon"] as? String,
                    pageAge: item["page_age"] as? String
                )
            } ?? []
            var errorCode: String?
            if let first = (raw["content"] as? [[String: Any]])?.first,
               first["type"] as? String == "web_search_tool_result_error" {
                errorCode = first["error_code"] as? String
            }
            let kind = BlockKind(rawValue: raw["kind"] as? String ?? "") ?? .search
            return .searchResults(id: id,
                                  toolUseID: raw["tool_use_id"] as? String ?? id,
                                  kind: kind,
                                  results: results,
                                  errorCode: errorCode)

        case "web_fetch_tool_result":
            let content = raw["content"] as? [String: Any]
            let isError = (content?["type"] as? String) == "web_fetch_tool_result_error"
            var page = FetchedPage(url: "", title: nil, publishedAt: nil, errorCode: nil)
            if isError {
                page.errorCode = content?["error_code"] as? String
                page.url = raw["tool_use_id"] as? String ?? ""
            } else {
                page.url = content?["url"] as? String ?? ""
                page.publishedAt = content?["published_at"] as? String
                if let document = content?["content"] as? [String: Any] {
                    page.title = document["title"] as? String
                }
            }
            let kind = BlockKind(rawValue: raw["kind"] as? String ?? "") ?? .readLink
            return .fetchedPage(id: id,
                                toolUseID: raw["tool_use_id"] as? String ?? id,
                                kind: kind,
                                page: page)

        default:
            return nil
        }
    }

    private static func parseCitations(_ raw: Any?) -> [Citation] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.map {
            Citation(url: $0["url"] as? String ?? "",
                     title: $0["title"] as? String,
                     citedText: $0["cited_text"] as? String)
        }
    }

    private static func parseAction(_ input: [String: Any]) -> ToolAction? {
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

    /// 从错误响应体里抠出可读信息，兼容 DeepSeek 的 `{"error":{"message":…}}`
    private static func extractMessage(from text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = json["error"] as? [String: Any] {
            return error["message"] as? String ?? ""
        }
        return json["message"] as? String ?? ""
    }
}
