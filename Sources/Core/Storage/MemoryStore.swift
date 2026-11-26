import Foundation
import SwiftData

/// 记忆的读写入口。
///
/// 和 `ConversationStore` 共用同一个 `ModelContainer`，界面侧照样用 `@Query` 读取，
/// 这里只负责写入前的校验：长度、容量、去重。
@MainActor
final class MemoryStore {

    static let shared = MemoryStore()

    private init() {}

    private var context: ModelContext { ConversationStore.shared.context }

    // MARK: - 读

    func all() -> [StoredMemory] {
        let descriptor = FetchDescriptor<StoredMemory>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<StoredMemory>())) ?? 0
    }

    // MARK: - 写

    enum Outcome {
        case saved(StoredMemory)
        /// 与已有条目重复，把命中的那条带回去，界面好提示「已经记过了」
        case duplicate(StoredMemory)
        case empty
        case tooLong(Int)
        case full(String)
    }

    /// 存一条记忆。调用方拿到 `.saved` 后再给用户回执。
    @discardableResult
    func remember(_ raw: String,
                  target: MemoryTarget = .user,
                  importance: MemoryImportance = .normal,
                  source: String = "manual",
                  conversationID: UUID? = nil) -> Outcome {

        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        guard text.count <= MemoryBudget.maxEntryLength else {
            return .tooLong(MemoryBudget.maxEntryLength)
        }

        let existing = all()
        if let duplicate = MemorySimilarity.duplicate(of: text, in: existing) {
            return .duplicate(duplicate)
        }

        let usage = MemoryBudget.usage(of: existing)
        guard usage.count < MemoryBudget.maxCount else {
            return .full("记忆已满 \(MemoryBudget.maxCount) 条，先在设置里清理几条")
        }
        let limit = MemoryBudget.maxCharacters
        guard usage.characters + text.count <= limit else {
            return .full("记忆字数已到 \(limit) 字，先在设置里清理几条")
        }

        let memory = StoredMemory(content: text,
                                  target: target,
                                  importance: importance,
                                  source: source,
                                  sourceConversationID: conversationID)
        context.insert(memory)
        save()
        return .saved(memory)
    }

    /// 编辑一条：改正文、分栏或重要性。改了正文就重新算更新时间。
    @discardableResult
    func update(_ memory: StoredMemory,
                content: String? = nil,
                target: MemoryTarget? = nil,
                importance: MemoryImportance? = nil) -> Outcome {

        if let content {
            let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .empty }
            guard text.count <= MemoryBudget.maxEntryLength else {
                return .tooLong(MemoryBudget.maxEntryLength)
            }
            // 和别的条目比对，比到自己不算重复
            let others = all().filter { $0.id != memory.id }
            if let duplicate = MemorySimilarity.duplicate(of: text, in: others) {
                return .duplicate(duplicate)
            }
            memory.content = text
        }
        if let target { memory.target = target }
        if let importance { memory.importance = importance }
        memory.updatedAt = Date()
        save()
        return .saved(memory)
    }

    func setEnabled(_ memory: StoredMemory, _ enabled: Bool) {
        memory.isEnabled = enabled
        memory.updatedAt = Date()
        save()
    }

    func delete(_ memory: StoredMemory) {
        context.delete(memory)
        save()
    }

    func deleteAll() {
        for memory in all() {
            context.delete(memory)
        }
        save()
    }

    /// 调试钩子灌样例数据用，跳过校验。
    func insertRaw(_ text: String,
                   target: MemoryTarget,
                   importance: MemoryImportance = .normal,
                   source: String = "manual") {
        context.insert(StoredMemory(content: text,
                                    target: target,
                                    importance: importance,
                                    source: source))
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("[MemoryStore] 保存失败：\(error)")
        }
    }
}
