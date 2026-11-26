import Foundation
import SwiftData

/// 本地会话仓库。消息以原始协议块 JSON 存储，不做结构化建模。
@MainActor
final class ConversationStore {

    static let shared = ConversationStore()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            StoredConversation.self,
            StoredMessage.self,
            StoredSkill.self,
            StoredMemory.self
        ])
        // DS_MEMORY_STORE=1 时整个库只在内存里，截图演示不污染真实数据
        let inMemory = ProcessInfo.processInfo.environment["DS_MEMORY_STORE"] == "1"
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 数据库打不开时退化到内存存储，至少让 App 能起来看界面
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [fallback])
            print("[ConversationStore] 本地库初始化失败，已退化为内存存储：\(error)")
        }
    }

    var context: ModelContext { container.mainContext }

    func all() -> [StoredConversation] {
        let descriptor = FetchDescriptor<StoredConversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func create(model: String) -> StoredConversation {
        let conversation = StoredConversation(model: model)
        context.insert(conversation)
        save()
        return conversation
    }

    func delete(_ conversation: StoredConversation) {
        context.delete(conversation)
        save()
    }

    /// 追加一条消息并维护会话的更新时间与标题。
    @discardableResult
    func append(to conversation: StoredConversation,
                role: String,
                blocks: [[String: Any]],
                plainText: String,
                status: String = "complete",
                usage: Usage? = nil,
                documents: [MessageDocument] = [],
                autoTitle: String? = nil) -> StoredMessage {
        let nextOrder = (conversation.messages.map(\.order).max() ?? -1) + 1
        let data = (try? JSONSerialization.data(withJSONObject: blocks)) ?? Data()
        let message = StoredMessage(order: nextOrder,
                                    role: role,
                                    blocksJSON: data,
                                    plainText: plainText,
                                    status: status,
                                    usage: usage,
                                    documents: documents)
        message.conversation = conversation
        context.insert(message)

        conversation.updatedAt = Date()
        if let autoTitle, !autoTitle.isEmpty, !conversation.titleIsManual {
            conversation.title = autoTitle
        }

        save()
        return message
    }

    /// 手动改名。置 `titleIsManual`，之后服务端再下发的标题不会覆盖它。
    func rename(_ conversation: StoredConversation, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversation.title = String(trimmed.prefix(60))
        conversation.titleIsManual = true
        save()
    }

    /// 删掉这个会话最后一条助手消息。重试失败/中断的那一轮时用，避免历史里留两条回复。
    func deleteLastAssistantMessage(in conversation: StoredConversation) {
        guard let last = conversation.messages
            .filter({ $0.role == "assistant" })
            .max(by: { $0.order < $1.order }) else { return }
        context.delete(last)
        conversation.updatedAt = Date()
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("[ConversationStore] 保存失败：\(error)")
        }
    }
}
