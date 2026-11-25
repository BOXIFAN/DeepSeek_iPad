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
    case blockStart(index: Int, block: ContentBlock, raw: Data)
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

    private let endpoint: URL
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // 首字节可能要等推理，给长一点；整条流的上限再放宽
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
        endpoint = Self.endpoint()
    }

    /// `DS_API_BASE` 可以把请求指到本地 mock，验证用；默认走官方地址。
    static func endpoint() -> URL {
        if let base = ProcessInfo.processInfo.environment["DS_API_BASE"],
           !base.isEmpty,
           let url = URL(string: base.trimmingCharacters(in: .whitespaces)) {
            return url.appendingPathComponent("anthropic/v1/messages")
        }
        return URL(string: "https://api.deepseek.com/anthropic/v1/messages")!
    }

    /// 请求体构造单独拎出来，方便自检和 mock 对拍。
    static func makeBody(messages: [[String: Any]], options: Options) -> [String: Any] {
        var body: [String: Any] = [
            "model": options.model,
            "stream": true,
            "max_tokens": options.maxTokens,
            "messages": messages
        ]
        if options.thinking {
            body["thinking"] = ["type": "enabled"]
            if let effort = options.thinkingEffort {
                body["output_config"] = ["effort": effort]
            }
        }
        if options.generateTitle {
            body["title"] = ["enabled": true]
        }
        if let systemPrompt = options.systemPrompt,
           !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        if options.webSearch {
            body["tools"] = [
                ["type": "deepseek_web_search", "name": "deepseek_web_search"],
                ["type": "deepseek_read_url", "name": "deepseek_read_url"]
            ]
        }
        return body
    }

    struct Options {
        var model = "deepseek-flash"
        var thinking = true
        /// 思考强度，对应请求体的 `output_config.effort`；nil 表示不发送（关闭思考）
        var thinkingEffort: String? = nil
        var webSearch = false
        var generateTitle = false
        var maxTokens = 8192
        /// 默认系统提示词 + 已启用技能拼好的内容，nil 表示不发送 system
        var systemPrompt: String? = nil
    }

    /// - Parameter messages: 已经组装好的协议消息数组，`content` 保持原始块结构。
    func stream(apiKey: String,
                messages: [[String: Any]],
                options: Options) -> AsyncThrowingStream<StreamEvent, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = Self.makeBody(messages: messages, options: options)

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

                    // 不能直接用 bytes.lines：它会把连续换行折叠，空行丢了 SSE 就永远攒不齐
                    // 一个事件。自己按字节切行，保留空行。
                    var parser = SSEParser()
                    var lineBytes: [UInt8] = []
                    var started = false

                    func handle(_ line: String) {
                        guard let sse = parser.consume(line) else { return }
                        for event in Self.decode(sse) {
                            continuation.yield(event)
                        }
                    }

                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {
                            var line = String(decoding: lineBytes, as: UTF8.self)
                            if line.hasSuffix("\r") { line.removeLast() }
                            lineBytes.removeAll(keepingCapacity: true)
                            started = true
                            handle(line)
                        } else {
                            lineBytes.append(byte)
                        }
                    }
                    if started, !lineBytes.isEmpty {
                        handle(String(decoding: lineBytes, as: UTF8.self))
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
                  let block = ContentBlock.make(from: raw, id: "stream-\(index)") else {
                return []
            }
            // 原始块 JSON 一并带出，多轮回传时要原样送回（signature 就藏在里面）
            let rawData = (try? JSONSerialization.data(withJSONObject: raw)) ?? Data()
            return [.blockStart(index: index, block: block, raw: rawData)]

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
