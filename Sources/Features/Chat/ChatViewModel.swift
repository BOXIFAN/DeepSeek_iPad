import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ChatViewModel {

    enum Role {
        case user
        case assistant
    }

    struct DisplayMessage: Identifiable {
        let id: String
        var role: Role
        /// 用户消息的正文
        var text: String
        /// 用户消息带的图片
        var images: [MessageImage] = []
        /// 用户消息带的文档（`file_id` 引用）
        var documents: [MessageDocument] = []
        /// 助手消息的内容块
        var blocks: [ContentBlock]
        var isStreaming = false
        var errorText: String?
        var stopReason: String?
        /// 工具结果的占位消息：协议里必须存在，界面上不显示
        var isToolResult = false
    }

    private(set) var messages: [DisplayMessage] = []
    private(set) var isStreaming = false
    /// 来自 `title` 参数的服务端会话标题
    private(set) var generatedTitle: String?
    /// 会话级用量：剩余上下文、缓存命中、最近一轮速度
    private(set) var metrics = SessionMetrics()
    /// 流式中按字符估算的实时速度，结束后换成服务端 usage 算出来的值
    private(set) var liveTokensPerSecond: Double?
    var errorText: String?
    /// 每次收到流事件自增，供视图层触发滚动跟随
    private(set) var streamTick = 0

    private(set) var currentConversation: StoredConversation?
    var conversationTitle: String = "新对话"

    private let store = ConversationStore.shared
    private let client = ChatClient()
    private var task: Task<Void, Never>?

    /// 协议层历史。助手轮存原始块数组，`signature` 等字段原样保留。
    private var history: [[String: Any]] = []
    /// content_block_start 下发的原始 JSON，回传时作为骨架
    private var blockTemplates: [Int: Data] = [:]
    /// signature_delta 累积
    private var blockSignatures: [Int: String] = [:]
    /// tool_use 的 input_json_delta 累积，按内容块下标存
    private var toolInputBuffers: [Int: String] = [:]
    /// 本轮已经连续跑了几次工具调用，防止无限续轮
    private var toolRoundDepth = 0
    /// finish 里续轮要复用同一套 Key 与参数
    private var lastAPIKey = ""
    private var lastOptions = ChatClient.Options()

    // 一轮请求的计量状态
    private var roundUsage: Usage?
    private var serverModel: String?
    private var firstDeltaAt: Date?
    private var lastSpeedSampleAt: Date?
    private var streamedCharacters = 0
    /// 当前轮次的代次。流式中切会话/新建时换一个，旧任务的收尾就不能再改指标或落库。
    private var roundID = UUID()
    /// 流式期间向系统申请的后台执行时间，切后台后还能再撑约 30 秒
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - 会话

    /// 开一个新会话。下次发送时才真正写库，避免点一下就留一条空会话。
    func startNew() {
        task?.cancel()
        task = nil
        roundID = UUID()
        isStreaming = false
        messages = []
        history = []
        blockTemplates = [:]
        blockSignatures = [:]
        toolInputBuffers = [:]
        toolRoundDepth = 0
        errorText = nil
        generatedTitle = nil
        currentConversation = nil
        conversationTitle = "新对话"
        resetRoundMetrics()
        metrics = SessionMetrics()
    }

    func load(_ conversation: StoredConversation) {
        task?.cancel()
        task = nil
        roundID = UUID()
        isStreaming = false
        currentConversation = conversation
        conversationTitle = conversation.title
        blockTemplates = [:]
        blockSignatures = [:]
        toolInputBuffers = [:]
        toolRoundDepth = 0
        errorText = nil
        generatedTitle = nil
        resetRoundMetrics()
        metrics = Self.metrics(for: conversation)

        messages = conversation.sortedMessages.map { stored in
            if stored.role == "user" {
                let images = stored.rawBlocks.compactMap(MessageImage.decode(from:))
                return DisplayMessage(id: stored.id.uuidString,
                                      role: .user,
                                      text: stored.plainText,
                                      images: images,
                                      documents: stored.documents,
                                      blocks: [])
            }
            return DisplayMessage(id: stored.id.uuidString,
                                  role: .assistant,
                                  text: "",
                                  blocks: ContentBlock.decodeAll(stored.rawBlocks),
                                  stopReason: stored.status)
        }

        history = conversation.sortedMessages.compactMap { stored in
            let content = stored.rawBlocks
            guard !content.isEmpty else { return nil }
            return ["role": stored.role, "content": content]
        }
        Self.repairDanglingToolUse(&history)
    }

    /// 历史末尾如果停在一个没有结果的 `tool_use`（工具执行前 App 被杀、数据库写了一半），
    /// 下一次请求会被服务端判成非法。补一条失败结果把它闭合，且不落库。
    private static func repairDanglingToolUse(_ history: inout [[String: Any]]) {
        guard let last = history.last,
              last["role"] as? String == "assistant",
              let content = last["content"] as? [[String: Any]] else { return }

        for block in content {
            guard block["type"] as? String == "tool_use",
                  let id = block["id"] as? String else { continue }
            history.append(["role": "user", "content": [[
                "type": "tool_result",
                "tool_use_id": id,
                "content": "这一轮没有执行完，结果缺失",
                "is_error": true
            ]]])
            return
        }
    }

    /// 调试钩子：`DS_DEMO_THREAD=1` 时灌入一段示例对话，供命令行截图核对排版。
    /// 只在启动时调用，不写库。
    func loadDemoThread(includeDocument: Bool = false) {
        task?.cancel()
        task = nil
        roundID = UUID()
        isStreaming = false
        history = []
        blockTemplates = [:]
        blockSignatures = [:]
        toolInputBuffers = [:]
        toolRoundDepth = 0
        errorText = nil
        currentConversation = nil
        let demoTitle = includeDocument ? "2026Q3 财报解读" : "DeepSeek 模型能力与价格"
        generatedTitle = demoTitle
        conversationTitle = demoTitle
        resetRoundMetrics()
        metrics = SessionMetrics(
            model: ModelCatalog.flash,
            contextWindow: ModelCatalog.contextWindow(for: ModelCatalog.flash),
            usedTokens: 28_460,
            lastUsage: Usage(inputTokens: 3_240,
                             outputTokens: 1_180,
                             cacheReadTokens: 24_040,
                             cacheCreationTokens: 0,
                             thinkingTokens: 620),
            tokensPerSecond: 46
        )
        let demos = includeDocument
            ? [MessageDocument(fileID: "file-api-demo",
                               filename: "2026Q3-财报.pdf",
                               byteCount: 2_480_000,
                               purpose: .textRecognition)]
            : []
        // 带文档的演示用一段短回复，保证附件卡和正文能在同一屏里截到
        let assistantBlocks: [ContentBlock] = includeDocument
            ? [.text(id: "demo-doc-text",
                     text: "已收到这份财报。文档里提到营收 42.6 亿元、同比增长 18%，毛利率 51%。需要按分部拆开讲，还是先看现金流？",
                     citations: [])]
            : SampleData.assistantBlocks
        messages = [
            DisplayMessage(id: "demo-user-1",
                           role: .user,
                           text: includeDocument ? "总结这份财报的要点" : SampleData.userQuestion,
                           images: [],
                           documents: demos,
                           blocks: []),
            DisplayMessage(id: "demo-assistant-1",
                           role: .assistant,
                           text: "",
                           blocks: assistantBlocks)
        ]
    }

    // MARK: - 发送

    func send(_ raw: String,
              images: [MessageImage] = [],
              documents: [MessageDocument] = [],
              apiKey: String,
              options: ChatClient.Options) {
        guard !isStreaming else { return }
        toolRoundDepth = 0
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty || !documents.isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorText = "还没填 API Key，先去设置里填一下"
            return
        }

        // 文档在前、图片在后、文字最后；模型先拿附件，再读问题
        var content: [[String: Any]] = documents.map(\.blockJSON)
        content += images.map(\.blockJSON)
        if !text.isEmpty {
            content.append(["type": "text", "text": text])
        }

        if currentConversation == nil {
            currentConversation = store.create(model: options.model)
        }
        if let conversation = currentConversation {
            // 首条用户消息顺便定标题，落库后重启才不会退回「新对话」
            let isFirstMessage = conversation.messages.isEmpty
            let fallbackTitle = Self.fallbackTitle(text: text, images: images, documents: documents)
            store.append(to: conversation,
                         role: "user",
                         blocks: content,
                         plainText: text,
                         documents: documents,
                         autoTitle: isFirstMessage ? fallbackTitle : nil)
            conversationTitle = conversation.title
        }

        messages.append(DisplayMessage(id: UUID().uuidString,
                                       role: .user,
                                       text: text,
                                       images: images,
                                       documents: documents,
                                       blocks: []))
        history.append([
            "role": "user",
            "content": content
        ])

        startRound(apiKey: apiKey, options: options)
    }

    /// 用户在历史浮层里改了当前会话的名字：顶栏立刻跟上，并让服务端标题失效。
    func applyManualTitle(_ title: String) {
        conversationTitle = title
        generatedTitle = nil
    }

    /// 这条助手回复能不能重试：失败或被中断，且确实是最后一条。
    var canRetryLastRound: Bool {
        guard !isStreaming, let last = messages.last, last.role == .assistant else { return false }
        return last.errorText != nil || last.stopReason == "failed" || last.stopReason == "stopped"
    }

    /// 重试最后一轮：丢掉失败的助手回复与它的历史 / 落库记录，用同一条用户消息重发。
    func retryLastRound(apiKey: String, options: ChatClient.Options) {
        guard canRetryLastRound else { return }
        guard let user = messages.last(where: { $0.role == .user && !$0.isToolResult }) else { return }
        toolRoundDepth = 0
        guard !apiKey.isEmpty else {
            errorText = "还没填 API Key，先去设置里填一下"
            return
        }

        messages.removeLast()
        if history.last?["role"] as? String == "assistant" {
            history.removeLast()
        }
        if let conversation = currentConversation {
            store.deleteLastAssistantMessage(in: conversation)
        }
        errorText = nil

        startRound(apiKey: apiKey, options: options)
    }

    private func startRound(apiKey: String, options: ChatClient.Options) {
        beginBackgroundTask()
        lastAPIKey = apiKey
        lastOptions = options
        let assistantID = UUID().uuidString
        messages.append(DisplayMessage(id: assistantID, role: .assistant, text: "", blocks: [], isStreaming: true))
        isStreaming = true
        errorText = nil
        generatedTitle = nil

        // 新一轮：保留上一轮的上下文占用（上下文只会涨），清掉上一轮的速度与缓存
        resetRoundMetrics()
        metrics.model = options.model
        metrics.contextWindow = ModelCatalog.contextWindow(for: options.model)
        metrics.tokensPerSecond = nil

        // 请求用的历史在这里拍快照：Task 真正跑起来之前用户可能已经切换会话
        let outgoing = history
        let round = UUID()
        roundID = round

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.endBackgroundTask() }
            let started = Date()
            do {
                for try await event in self.client.stream(apiKey: apiKey,
                                                          messages: outgoing,
                                                          options: options) {
                    if Task.isCancelled { break }
                    guard round == self.roundID else { break }
                    self.apply(event, to: assistantID, startedAt: started)
                }
            } catch {
                // 这一轮已经被 startNew/load 作废：不弹错、不改当前会话
                guard round == self.roundID else { return }
                self.errorText = error.localizedDescription
                self.update(assistantID) { message in
                    message.errorText = error.localizedDescription
                    message.isStreaming = false
                    message.stopReason = "failed"
                }
            }
            self.finish(assistantID, roundID: round)
        }
    }

    /// 会话标题的本地兜底：有正文用正文，只有附件就用附件名。
    private static func fallbackTitle(text: String,
                                      images: [MessageImage],
                                      documents: [MessageDocument]) -> String {
        if !text.isEmpty { return String(text.prefix(24)) }
        if let first = documents.first { return first.filename }
        if !images.isEmpty { return "图片 · \(images.count) 张" }
        return "新对话"
    }

    func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
        for index in messages.indices where messages[index].isStreaming {
            messages[index].isStreaming = false
            messages[index].stopReason = "stopped"
        }
        finish(messages.last(where: { $0.role == .assistant })?.id, roundID: roundID)
    }

    // MARK: - 事件应用

    private func apply(_ event: StreamEvent, to messageID: String, startedAt: Date) {
        streamTick &+= 1
        switch event {
        case .messageStart(let model, let usage):
            if let model, !model.isEmpty {
                serverModel = model
                metrics.model = model
                metrics.contextWindow = ModelCatalog.contextWindow(for: model)
            }
            if let usage {
                roundUsage = (roundUsage ?? Usage()).merged(with: usage)
                // 输入与缓存这一半已经确定，先落到指标上，流式过程中「缓存命中」就不会空着
                metrics.apply(usage, model: model, tokensPerSecond: nil)
            }

        case .blockStart(let index, let block, let raw):
            blockTemplates[index] = raw
            update(messageID) { message in
                if index < message.blocks.count {
                    message.blocks[index] = block
                } else {
                    message.blocks.append(block)
                }
            }

        case .blockDelta(let index, let delta):
            if case .toolInput(let fragment) = delta {
                toolInputBuffers[index, default: ""] += fragment
                let full = toolInputBuffers[index] ?? "{}"
                update(messageID) { message in
                    guard index < message.blocks.count,
                          case .toolUse(let id, let name, _) = message.blocks[index] else { return }
                    message.blocks[index] = .toolUse(id: id, name: name, inputJSON: full)
                }
            } else if case .signature(let chunk) = delta {
                blockSignatures[index] = (blockSignatures[index] ?? "") + chunk
            } else {
                noteProgress(delta)
            }
            update(messageID) { message in
                guard index < message.blocks.count else { return }
                message.blocks[index] = Self.apply(delta, to: message.blocks[index])
            }

        case .blockStop(let index):
            update(messageID) { message in
                guard index < message.blocks.count,
                      case .thinking(let id, let text, nil) = message.blocks[index] else { return }
                message.blocks[index] = .thinking(id: id,
                                                 text: text,
                                                 duration: Date().timeIntervalSince(startedAt))
            }

        case .messageDelta(let stopReason, let title, let usage):
            if let usage {
                roundUsage = (roundUsage ?? Usage()).merged(with: usage)
            }
            if let title, !title.isEmpty {
                generatedTitle = title
            }
            if let stopReason {
                update(messageID) { $0.stopReason = stopReason }
            }

        case .messageStop:
            break

        case .failure(let message):
            errorText = message
            update(messageID) { item in
                item.errorText = message
                item.isStreaming = false
                item.stopReason = "failed"
            }
        }
    }

    private static func apply(_ delta: BlockDelta, to block: ContentBlock) -> ContentBlock {
        switch (block, delta) {
        case (.thinking(let id, let text, let duration), .thinking(let chunk)):
            return .thinking(id: id, text: text + chunk, duration: duration)

        case (.thinking(let id, let text, let duration), .signature):
            return .thinking(id: id, text: text, duration: duration)

        case (.text(let id, let text, let citations), .text(let chunk)):
            return .text(id: id, text: text + chunk, citations: citations)

        case (.text(let id, let text, let citations), .citation(let citation)):
            return .text(id: id, text: text, citations: citations + [citation])

        case (let block, .toolInput):
            return block

        default:
            return block
        }
    }

    // MARK: - 收尾

    private func finish(_ messageID: String?, roundID: UUID? = nil) {
        // 已被 startNew/load 作废的旧任务：不改当前会话的指标，也不往新会话里写消息
        if let roundID, roundID != self.roundID { return }

        isStreaming = false
        if let messageID {
            update(messageID) { $0.isStreaming = false }
        }

        // 先结算本轮的用量：usage 缺失时用字符数兜底，至少让卡片有数可看
        let endedAt = Date()
        let generationSeconds = firstDeltaAt.map { endedAt.timeIntervalSince($0) } ?? 0
        var usage = roundUsage ?? Usage()
        if usage.outputTokens == 0, streamedCharacters > 0 {
            usage.outputTokens = SessionMetrics.estimatedTokens(forCharacters: streamedCharacters)
        }
        let speed: Double? = generationSeconds > 0.25 && usage.outputTokens > 0
            ? Double(usage.outputTokens) / generationSeconds
            : nil
        metrics.apply(usage, model: serverModel, tokensPerSecond: speed)
        liveTokensPerSecond = nil
        lastSpeedSampleAt = nil

        guard let last = messages.last(where: { $0.role == .assistant }) else { return }

        var content = buildAssistantContent(from: last)
        let toolCall = Self.firstToolCall(in: content)
        // 停止、失败、截断时不续轮；这时也不能把没结果的 tool_use 留在历史里，
        // 下一次请求会因为「assistant 带 tool_use 但缺少 tool_result」被拒。
        let willContinue = toolCall != nil
            && last.errorText == nil
            && last.stopReason != "stopped"
            && last.stopReason != "max_tokens"
            && toolRoundDepth < 2

        if toolCall != nil, !willContinue {
            content.removeAll { $0["type"] as? String == "tool_use" }
        }

        blockTemplates.removeAll()
        blockSignatures.removeAll()
        toolInputBuffers.removeAll()

        guard !content.isEmpty else {
            // 一个块都没收到：给明确的失败态，别让消息停在半空
            if last.stopReason != "stopped", last.errorText == nil {
                let message = "没有收到任何内容，重试一次"
                errorText = message
                update(last.id) {
                    $0.errorText = message
                    $0.stopReason = "failed"
                }
            }
            return
        }

        history.append(["role": "assistant", "content": content])

        let plain = last.blocks.compactMap { block -> String? in
            if case .text(_, let text, _) = block { return text }
            return nil
        }.joined()

        if let conversation = currentConversation {
            store.append(to: conversation,
                         role: "assistant",
                         blocks: content,
                         plainText: plain,
                         status: last.stopReason ?? "complete",
                         usage: usage.isEmpty ? nil : usage,
                         autoTitle: generatedTitle)
            conversationTitle = conversation.title
        }

        guard let toolCall, willContinue else { return }

        // 执行工具，把结果作为紧接着的 user 消息回传，再起一轮。
        // 协议要求：assistant 带 tool_use 时，紧跟的 user 必须给齐全部 tool_result，
        // 且 tool_result 块要排在文本之前。
        let result = Self.performTool(toolCall, conversationID: currentConversation?.id)
        let resultBlocks: [[String: Any]] = [[
            "type": "tool_result",
            "tool_use_id": toolCall.id,
            "content": result
        ]]
        history.append(["role": "user", "content": resultBlocks])
        messages.append(DisplayMessage(id: UUID().uuidString,
                                       role: .user,
                                       text: "",
                                       blocks: [],
                                       isToolResult: true))
        if let conversation = currentConversation {
            store.append(to: conversation,
                         role: "user",
                         blocks: resultBlocks,
                         plainText: "")
        }
        toolRoundDepth += 1
        startRound(apiKey: lastAPIKey, options: lastOptions)
    }

    /// 从已经合并好的块数组里取第一个工具调用；目前也只有 `remember` 一个工具。
    /// 不能从展示块里取：展示块的 input 在流式过程中才逐步拼起来。
    private static func firstToolCall(in content: [[String: Any]])
        -> (id: String, name: String, inputJSON: String)? {
        for block in content {
            guard block["type"] as? String == "tool_use",
                  let id = block["id"] as? String,
                  let name = block["name"] as? String else { continue }
            let input = block["input"] as? [String: Any] ?? [:]
            let data = (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8)
            return (id, name, String(data: data, encoding: .utf8) ?? "{}")
        }
        return nil
    }

    /// 执行客户端工具，返回给模型看的结果文本。
    private static func performTool(_ call: (id: String, name: String, inputJSON: String),
                                    conversationID: UUID?) -> String {
        guard call.name == "remember" else {
            return "未知工具，没有执行：\(call.name)"
        }
        guard let data = call.inputJSON.data(using: .utf8),
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "参数不是合法 JSON，没有写入"
        }
        let content = (input["content"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return "参数里没有 content，没有写入" }

        let target = MemoryTarget(rawValue: input["target"] as? String ?? "") ?? .user
        let importance = MemoryImportance(rawValue: input["importance"] as? String ?? "") ?? .normal

        switch MemoryStore.shared.remember(content,
                                           target: target,
                                           importance: importance,
                                           source: "tool",
                                           conversationID: conversationID) {
        case .saved:
            return "已记住（\(target.title)）：\(content)"
        case .duplicate(let other):
            return "已有相同记忆，没有重复写入：\(other.trimmedContent)"
        case .tooLong(let limit):
            return "内容超过 \(limit) 字，没有写入；请压缩成一句话。"
        case .full(let message):
            return "\(message)。请提醒用户先清理记忆。"
        case .empty:
            return "内容为空，没有写入。"
        }
    }

    /// 用模板骨架 + 最终内容还原原始块数组。
    ///
    /// 直接回传 `content_block_start` 的模板会丢掉流式拼出来的正文，只拼纯文本又会
    /// 丢掉 `signature` 与 `encrypted_content`。这里两条都保住。
    private func buildAssistantContent(from message: DisplayMessage) -> [[String: Any]] {
        var content: [[String: Any]] = []
        for index in blockTemplates.keys.sorted() {
            guard let data = blockTemplates[index],
                  var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if index < message.blocks.count {
                switch message.blocks[index] {
                case .thinking(_, let text, _):
                    dict["thinking"] = text
                    if let signature = blockSignatures[index], !signature.isEmpty {
                        dict["signature"] = signature
                    }
                case .text(_, let text, _):
                    dict["text"] = text
                case .toolUse:
                    if let buffered = toolInputBuffers[index],
                       !buffered.isEmpty,
                       let parsed = try? JSONSerialization.jsonObject(with: Data(buffered.utf8)) {
                        dict["input"] = parsed
                    }
                default:
                    break
                }
            }
            content.append(dict)
        }
        return content
    }

    private func update(_ messageID: String, _ mutate: (inout DisplayMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        mutate(&messages[index])
    }

    // MARK: - 用量计量

    private func resetRoundMetrics() {
        roundUsage = nil
        serverModel = nil
        firstDeltaAt = nil
        lastSpeedSampleAt = nil
        streamedCharacters = 0
        liveTokensPerSecond = nil
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "chat-stream") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// 从落库的最近一轮用量恢复会话指标，切换历史会话时数字才不会归零。
    private static func metrics(for conversation: StoredConversation) -> SessionMetrics {
        var metrics = SessionMetrics()
        metrics.reset(for: conversation.model)
        if let usage = conversation.sortedMessages.reversed().compactMap(\.usage).first {
            metrics.lastUsage = usage
            metrics.usedTokens = usage.totalInputTokens + usage.outputTokens
        }
        return metrics
    }

    /// 流式过程中按已生成字符估算速度，每 0.2 秒最多采一次样，避免每个 delta 都重算。
    private func noteProgress(_ delta: BlockDelta) {
        let count: Int
        switch delta {
        case .thinking(let text), .text(let text):
            count = text.count
        case .signature, .citation, .toolInput:
            return
        }
        guard count > 0 else { return }

        streamedCharacters += count
        let now = Date()
        if firstDeltaAt == nil {
            firstDeltaAt = now
            return
        }
        guard let first = firstDeltaAt else { return }
        let elapsed = now.timeIntervalSince(first)
        guard elapsed >= 0.3 else { return }
        if let lastSpeedSampleAt, now.timeIntervalSince(lastSpeedSampleAt) < 0.2 { return }

        let tokens = SessionMetrics.estimatedTokens(forCharacters: streamedCharacters)
        liveTokensPerSecond = Double(tokens) / elapsed
        lastSpeedSampleAt = now
    }
}
