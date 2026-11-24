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
    /// 每次收到流事件自增，供视图层触发滚动跟随。
    private(set) var streamTick = 0

    private let client = ChatClient()
    private var task: Task<Void, Never>?

    /// 协议层历史。TODO(里程碑 1)：改成把每轮 assistant 的原始块 JSON 原样回传，
    /// 现在只回传正文，多轮会丢失「模型读过哪个网页」这类上下文。
    private var history: [[String: Any]] = []

    // MARK: - 发送

    func send(_ raw: String, apiKey: String, options: ChatClient.Options) {
        guard !isStreaming else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorText = "还没填 API Key，先去设置里填一下"
            return
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
        persistLastAssistant()
    }

    func reset() {
        task?.cancel()
        task = nil
        messages = []
        history = []
        isStreaming = false
        errorText = nil
        generatedTitle = nil
    }

    // MARK: - 事件应用

    private func apply(_ event: StreamEvent, to messageID: String, startedAt: Date) {
        streamTick &+= 1
        switch event {
        case .messageStart:
            break

        case .blockStart(let index, let block):
            update(messageID) { message in
                if index < message.blocks.count {
                    message.blocks[index] = block
                } else {
                    message.blocks.append(block)
                }
            }

        case .blockDelta(let index, let delta):
            update(messageID) { message in
                guard index < message.blocks.count else { return }
                message.blocks[index] = Self.apply(delta, to: message.blocks[index])
            }

        case .blockStop(let index):
            // 思考块结束时补上用时，供「已深度思考（用时 N 秒）」展示
            update(messageID) { message in
                guard index < message.blocks.count,
                      case .thinking(let id, let text, nil) = message.blocks[index] else { return }
                message.blocks[index] = .thinking(
                    id: id,
                    text: text,
                    duration: Date().timeIntervalSince(startedAt)
                )
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
            update(messageID) { message2 in
                message2.errorText = message
                message2.isStreaming = false
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

    private func finish(_ messageID: String) {
        isStreaming = false
        update(messageID) { $0.isStreaming = false }
        persistLastAssistant()
    }

    private func persistLastAssistant() {
        guard let last = messages.last(where: { $0.role == .assistant }) else { return }
        let text = last.blocks.compactMap { block -> String? in
            if case .text(_, let text, _) = block { return text }
            return nil
        }.joined()
        guard !text.isEmpty else { return }
        history.append([
            "role": "assistant",
            "content": [["type": "text", "text": text]]
        ])
    }

    private func update(_ messageID: String, _ mutate: (inout DisplayMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        mutate(&messages[index])
    }
}
