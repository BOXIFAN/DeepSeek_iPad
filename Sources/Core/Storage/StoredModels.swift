import Foundation
import SwiftData

/// 持久化的会话。
///
/// 消息内容以「原始协议块数组」的 JSON 存进 `StoredMessage.blocksJSON`，
/// 不走结构化建模。API 加新块类型时不用迁移数据库，回传时也能原样送回
/// （`signature`、`encrypted_content` 这些字段全在里面）。
@Model
final class StoredConversation {

    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var model: String
    /// 用户手动改过标题后置 true，服务端自动标题不再覆盖
    var titleIsManual: Bool

    @Relationship(deleteRule: .cascade, inverse: \StoredMessage.conversation)
    var messages: [StoredMessage] = []

    init(title: String = "新对话", model: String = "deepseek-flash") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.model = model
        self.titleIsManual = false
    }

    var sortedMessages: [StoredMessage] {
        messages.sorted { $0.order < $1.order }
    }
}

@Model
final class StoredMessage {

    @Attribute(.unique) var id: UUID
    /// 会话内的顺序，从 0 递增
    var order: Int
    /// "user" / "assistant"
    var role: String
    /// 协议层 content 数组的 JSON
    var blocksJSON: Data
    /// 提取的纯文本，供列表预览与搜索
    var plainText: String
    /// "complete" / "stopped" / "failed" / "refused"
    var status: String
    var createdAt: Date

    var conversation: StoredConversation?

    init(order: Int,
         role: String,
         blocksJSON: Data,
         plainText: String,
         status: String = "complete") {
        self.id = UUID()
        self.order = order
        self.role = role
        self.blocksJSON = blocksJSON
        self.plainText = plainText
        self.status = status
        self.createdAt = Date()
    }

    var rawBlocks: [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: blocksJSON)) as? [[String: Any]] ?? []
    }
}
