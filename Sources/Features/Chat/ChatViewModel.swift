import Foundation
import Observation

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
        /// 助手消息的内容块
        var blocks: [ContentBlock]
        var isStreaming = false
        var errorText: String?
        var stopReason: String?
    }

    private(set) var messages: [DisplayMessage] = []
    private(set) var isStreaming = false
    /// 来自 `title` 参数的服务端会话标题
    private(set) var generatedTitle: String?
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

    // MARK: - 会话

    /// 开一个新会话。下次发送时才真正写库，避免点一下就留一条空会话。
    func startNew() {
        task?.cancel()
        task = nil
        isStreaming = false
        messages = []
        history = []
        blockTemplates = [:]
        blockSignatures = [:]
        errorText = nil
        generatedTitle = nil
        currentConversation = nil
        conversationTitle = "新对话"
    }

    func load(_ conversation: StoredConversation) {
        task?.cancel()
        task = nil
        isStreaming = false
        currentConversation = conversation
        conversationTitle = conversation.title
        blockTemplates = [:]
        blockSignatures = [:]
        errorText = nil
        generatedTitle = nil

        messages = conversation.sortedMessages.map { stored in
            if stored.role == "user" {
                return DisplayMessage(id: stored.id.uuidString,
                                      role: .user,
                                      text: stored.plainText,
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
    }

    // MARK: - 发送

    func send(_ raw: String, apiKey: String, options: ChatClient.Options) {
        guard !isStreaming else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorText = "还没填 API Key，先去设置里填一下"
            return
        }

        if currentConversation == nil {
            currentConversation = store.create(model: options.model)
        }
        if let conversation = currentConversation {
            // 首条用户消息顺便定标题，落库后重启才不会退回「新对话」
            let isFirstMessage = conversation.messages.isEmpty
            store.append(to: conversation,
                         role: "user",
                         blocks: [["type": "text", "text": text]],
                         plainText: text,
                         autoTitle: isFirstMessage ? String(text.prefix(24)) : nil)
            conversationTitle = conversation.title
        }

        messages.append(DisplayMessage(id: UUID().uuidString, role: .user, text: text, blocks: []))
        history.append([
            "role": "user",
            "content": [["type": "text", "text": text]]
        ])

        let assistantID = UUID().uuidString
        messages.append(DisplayMessage(id: assistantID, role: .assistant, text: "", blocks: [], isStreaming: true))
        isStreaming = true
        errorText = nil
        generatedTitle = nil

        task = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            do {
                for try await event in self.client.stream(apiKey: apiKey, messages: self.history, options: options) {
                    if Task.isCancelled { break }
                    self.apply(event, to: assistantID, startedAt: started)
                }
            } catch {
                self.errorText = error.localizedDescription
                self.update(assistantID) { message in
                    message.errorText = error.localizedDescription
                    message.isStreaming = false
                    message.stopReason = "failed"
                }
            }
            self.finish(assistantID)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
        for index in messages.indices where messages[index].isStreaming {
            messages[index].isStreaming = false
            messages[index].stopReason = "stopped"
        }
        finish(messages.last(where: { $0.role == .assistant })?.id)
    }

    // MARK: - 事件应用

    private func apply(_ event: StreamEvent, to messageID: String, startedAt: Date) {
        streamTick &+= 1
        switch event {
        case .messageStart:
            break

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
            if case .signature(let chunk) = delta {
                blockSignatures[index] = (blockSignatures[index] ?? "") + chunk
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

        case .messageDelta(let stopReason, let title, _):
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

        default:
            return block
        }
    }

    // MARK: - 收尾

    private func finish(_ messageID: String?) {
        isStreaming = false
        if let messageID {
            update(messageID) { $0.isStreaming = false }
        }

        guard let last = messages.last(where: { $0.role == .assistant }) else { return }
        let content = buildAssistantContent(from: last)

        blockTemplates.removeAll()
        blockSignatures.removeAll()

        guard !content.isEmpty else { return }

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
                         autoTitle: generatedTitle)
            conversationTitle = conversation.title
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
}
