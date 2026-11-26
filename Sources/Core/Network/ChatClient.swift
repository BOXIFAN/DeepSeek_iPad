import Foundation

// MARK: - 用量

/// 一轮请求的 token 用量。
///
/// 两套口径都认：
/// - **Anthropic 口径**（`/anthropic/v1/messages` 的正式语义）：`input_tokens` 只算未命中
///   缓存的部分，总输入 = `input_tokens` + `cache_read_input_tokens` + `cache_creation_input_tokens`。
/// - **DeepSeek 原生口径**：`prompt_tokens` 已经是总数，命中量在 `prompt_cache_hit_tokens`。
///   兼容层如果直接透传原生字段，就用 `inputIncludesCache` 标住，避免把命中量加两遍。
struct Usage: Sendable, Equatable, Codable {
    var inputTokens = 0
    var outputTokens = 0
    /// 命中缓存、按折扣计价的输入
    var cacheReadTokens = 0
    /// 写入缓存的输入（Anthropic 口径才有，不额外计费一次上下文）
    var cacheCreationTokens = 0
    var thinkingTokens = 0
    /// `inputTokens` 是否已经包含缓存命中（原生 `prompt_tokens` 口径）
    var inputIncludesCache = false

    /// 下一轮请求大概要带上的输入量，也就是这一轮占掉的上下文。
    var totalInputTokens: Int {
        inputIncludesCache
            ? max(inputTokens, cacheReadTokens + cacheCreationTokens)
            : inputTokens + cacheReadTokens + cacheCreationTokens
    }

    var totalTokens: Int {
        totalInputTokens + outputTokens
    }

    var isEmpty: Bool {
        totalTokens == 0
    }

    /// 命中率的分母是总输入，不是未命中部分。没输入时返回 nil，界面显示「—」。
    var cacheHitRate: Double? {
        let total = totalInputTokens
        guard total > 0 else { return nil }
        return min(1, Double(cacheReadTokens) / Double(total))
    }

    static func from(_ dict: [String: Any]?) -> Usage? {
        guard let dict else { return nil }

        var usage = Usage()
        usage.inputTokens = int(dict["input_tokens"]) ?? int(dict["prompt_tokens"]) ?? 0
        usage.outputTokens = int(dict["output_tokens"]) ?? int(dict["completion_tokens"]) ?? 0

        let read = int(dict["cache_read_input_tokens"])
        let creation = int(dict["cache_creation_input_tokens"])
        if read != nil || creation != nil {
            usage.cacheReadTokens = read ?? 0
            usage.cacheCreationTokens = creation ?? 0
            usage.inputIncludesCache = false
        } else if let hit = int(dict["prompt_cache_hit_tokens"]) {
            usage.cacheReadTokens = hit
            usage.cacheCreationTokens = 0
            usage.inputIncludesCache = true
            usage.inputTokens = int(dict["prompt_tokens"]) ?? usage.inputTokens
        }

        if let details = dict["output_tokens_details"] as? [String: Any] {
            usage.thinkingTokens = int(details["thinking_tokens"]) ?? 0
        }
        return usage
    }

    /// 流式里字段分两段到：`message_start` 给输入与缓存，`message_delta` 给最终输出。
    /// 各自缺的字段保留原值，不能拿 0 覆盖。
    func merged(with other: Usage) -> Usage {
        var result = self
        if other.inputTokens > 0 { result.inputTokens = other.inputTokens }
        if other.outputTokens > 0 { result.outputTokens = max(result.outputTokens, other.outputTokens) }
        if other.cacheReadTokens > 0 { result.cacheReadTokens = other.cacheReadTokens }
        if other.cacheCreationTokens > 0 { result.cacheCreationTokens = other.cacheCreationTokens }
        if other.thinkingTokens > 0 { result.thinkingTokens = other.thinkingTokens }
        if other.inputIncludesCache { result.inputIncludesCache = true }
        return result
    }

    /// JSON 数字既可能来 Int 也可能来 Double（某些代理会写成 128.0）。
    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: return value
        case let value as Double: return Int(value)
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value)
        default: return nil
        }
    }
}

// MARK: - 增量

enum BlockDelta: Sendable {
    case thinking(String)
    case signature(String)
    case text(String)
    case citation(Citation)
    /// 客户端工具的参数分片（`input_json_delta.partial_json`）
    case toolInput(String)
}

// MARK: - 流事件

/// 一次流式响应被拆成的事件序列。顺序与官方文档一致：
/// message_start → (blockStart → delta… → blockStop)* → message_delta → message_stop
enum StreamEvent: Sendable {
    /// `message_start` 里带首段 usage（输入与缓存命中）和服务端认定的模型名。
    case messageStart(model: String?, usage: Usage?)
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
    /// 连接提前断开，没收到 message_stop
    case incompleteStream

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
        case .incompleteStream:
            return "回复没有正常结束，可能中途断线；重试一次"
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
        config.timeoutIntervalForRequest = 180
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
        var tools: [[String: Any]] = []
        if options.memoryTools {
            tools.append(memoryTool)
        }
        if options.webSearch {
            tools.append(["type": "deepseek_web_search", "name": "deepseek_web_search"])
            tools.append(["type": "deepseek_read_url", "name": "deepseek_read_url"])
        }
        if !tools.isEmpty {
            body["tools"] = tools
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
        var maxTokens = 32_768
        /// 默认系统提示词 + 已启用技能拼好的内容，nil 表示不发送 system
        var systemPrompt: String? = nil
        /// 是否带上 `remember` 工具，让模型在对话里自己写记忆
        var memoryTools = false
    }

    /// 客户端工具：不能带 `type` 字段，带了会被当成服务端工具解析并返回 422。
    static let memoryTool: [String: Any] = [
        "name": "remember",
        "description": """
        把一条长期有效的事实写进用户的记忆库，之后每次对话都会带上。只在用户明确说出偏好、身份、        长期约定，或你确认了一个以后还会用到的项目事实时调用。临时任务进度、代码里的普通细节、        能从上下文推断的信息、你不确定的内容都不要记。一次只记一件事，用陈述句，不超过 200 字。        写入前先看 system 里的长期记忆段落，已经有的不要重复写。
        """,
        "input_schema": [
            "type": "object",
            "properties": [
                "content": [
                    "type": "string",
                    "description": "一句话事实，陈述句，不超过 200 字"
                ],
                "target": [
                    "type": "string",
                    "enum": ["user", "memory"],
                    "description": "user 放用户的身份与偏好；memory 放项目、环境与约定"
                ],
                "importance": [
                    "type": "string",
                    "enum": ["critical", "normal", "low"],
                    "description": "用户明确要求永远或必须遵守的用 critical"
                ]
            ],
            "required": ["content"]
        ]
    ]

    /// 请求体里只要出现 `document` / `file` 块，就要带 Files API 的 beta 头。
    /// 由客户端自动判断，调用方不用记这条规则。
    static func needsFilesBeta(messages: [[String: Any]]) -> Bool {
        for message in messages {
            guard let content = message["content"] as? [[String: Any]] else { continue }
            for block in content {
                let type = block["type"] as? String
                if type == "document" || type == "file" {
                    return true
                }
            }
        }
        return false
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
                    if Self.needsFilesBeta(messages: messages) {
                        request.setValue("files-api-2025-04-14", forHTTPHeaderField: "anthropic-beta")
                    }
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
                    var sawMessageStop = false

                    func handle(_ line: String) {
                        guard let sse = parser.consume(line) else { return }
                        for event in Self.decode(sse) {
                            if case .messageStop = event { sawMessageStop = true }
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

                    // 连接提前断开时 URLSession 不报错，只是字节流结束。
                    // 没有 message_stop 就说明这一轮没正常收完，当作中断处理，
                    // 否则消息会静默停在半空（思考块有了、正文没有）。
                    if !Task.isCancelled && !sawMessageStop {
                        throw ChatError.incompleteStream
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
            let message = json["message"] as? [String: Any]
            let model = (message?["model"] as? String) ?? (json["model"] as? String)
            let usage = Usage.from((message?["usage"] as? [String: Any])
                                    ?? (json["usage"] as? [String: Any]))
            return [.messageStart(model: model, usage: usage)]

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
        case "input_json_delta":
            return .toolInput(delta["partial_json"] as? String ?? "")
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
