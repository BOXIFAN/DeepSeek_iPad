import Foundation

/// 会话。里程碑 1 换成 SwiftData 模型，预览阶段先用内存结构。
struct Conversation: Identifiable, Hashable {
    let id: UUID
    var title: String
    var preview: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, preview: String, minutesAgo: Int) {
        self.id = id
        self.title = title
        self.preview = preview
        self.updatedAt = Date().addingTimeInterval(-Double(minutesAgo) * 60)
    }
}

extension Conversation {
    static let samples: [Conversation] = [
        Conversation(
            title: "DeepSeek 模型能力与价格",
            preview: "现在的主力是两个模型：deepseek-flash 便宜、快…",
            minutesAgo: 2
        ),
        Conversation(
            title: "Swift 并发里的 actor 隔离",
            preview: "在 Swift 6 严格并发模式下，MainActor 隔离的…",
            minutesAgo: 96
        ),
        Conversation(
            title: "把长文档拆成章节再总结",
            preview: "先按一级标题切分，每段单独总结，最后合并…",
            minutesAgo: 1500
        ),
        Conversation(
            title: "SQLite 索引选择",
            preview: "复合索引的列顺序决定了能命中哪些查询前缀…",
            minutesAgo: 2900
        )
    ]
}
