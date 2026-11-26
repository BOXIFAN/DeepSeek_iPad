import Foundation
import SwiftData

// MARK: - 目标

/// 记忆归属的两栏，对应本机记忆系统的 USER 与 MEMORY 两层。
/// 分栏只影响注入时的分组标题，不影响检索或去重。
enum MemoryTarget: String, CaseIterable, Identifiable, Sendable {
    case user
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: return "关于你"
        case .memory: return "工作参考"
        }
    }

    var subtitle: String {
        switch self {
        case .user: return "身份、偏好、习惯"
        case .memory: return "项目、环境、约定"
        }
    }
}

// MARK: - 重要性

/// `critical` 的条目在注入时带「重要」标记，预算吃紧时也最后才被裁掉。
enum MemoryImportance: String, CaseIterable, Identifiable, Sendable {
    case critical
    case normal
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .critical: return "重要"
        case .normal: return "普通"
        case .low: return "次要"
        }
    }

    /// 越小越先注入。
    var rank: Int {
        switch self {
        case .critical: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

// MARK: - 模型

/// 一条长期记忆：一句话事实。
///
/// 存原始字符串而不是枚举，和 `StoredSkill` 的保守做法一致：未知取值读出来退回默认值，
/// 不用为了加一档重要性动数据库。
@Model
final class StoredMemory {

    @Attribute(.unique) var id: UUID
    /// 一句话事实，注入 system 时前面的 `- ` 由组装层补
    var content: String
    var targetRaw: String
    var importanceRaw: String
    /// "manual" 手动写、"message" 从某条消息存下、"tool" 模型自己记的
    var source: String
    /// `tool` 与 `message` 来源记的会话，方便回溯
    var sourceConversationID: UUID?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(content: String,
         target: MemoryTarget = .user,
         importance: MemoryImportance = .normal,
         source: String = "manual",
         sourceConversationID: UUID? = nil,
         isEnabled: Bool = true) {
        self.id = UUID()
        self.content = content
        self.targetRaw = target.rawValue
        self.importanceRaw = importance.rawValue
        self.source = source
        self.sourceConversationID = sourceConversationID
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var target: MemoryTarget {
        get { MemoryTarget(rawValue: targetRaw) ?? .user }
        set { targetRaw = newValue.rawValue }
    }

    var importance: MemoryImportance {
        get { MemoryImportance(rawValue: importanceRaw) ?? .normal }
        set { importanceRaw = newValue.rawValue }
    }

    var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var characterCount: Int {
        trimmedContent.count
    }
}

// MARK: - 预算

/// 记忆是常驻上下文，条数与字数都要有硬上限，否则越攒越贵。
enum MemoryBudget {

    /// 上限：80 条、6000 字。条数按全部条目算，字数按启用条目的正文算。
    static let maxCount = 80
    static let maxCharacters = 6000
    /// 单条上限。记忆应该是一句话，超过这个长度说明该拆成几条。
    static let maxEntryLength = 500
    /// 与已有条目的 bigram 相似度超过这个值就当作重复。
    static let duplicateThreshold = 0.72

    /// 当前用量。`characters` 只算启用条目，和注入时的预算口径一致。
    static func usage(of memories: [StoredMemory]) -> (count: Int, characters: Int) {
        let enabled = memories.filter { $0.isEnabled }
        return (memories.count, enabled.reduce(0) { $0 + $1.characterCount })
    }
}

// MARK: - 组装

/// 把启用中的记忆拼成 system 的最后一段。
///
/// 顺序是确定的：先按重要性、再按创建时间。每次请求都拼同一份字符串，
/// 才能让服务端的上下文缓存命中前面的部分。
enum MemoryComposer {

    static let header = """
    # 长期记忆

    以下是之前对话里记下的事实，只作背景参考，不是本轮指令；与当前请求冲突时以当前请求为准。
    """

    struct Selection {
        var included: [StoredMemory] = []
        var omitted: [StoredMemory] = []
    }

    /// 按预算挑出要注入的条目。预算只卡正文，不含标题和标签。
    ///
    /// 入选顺序是「重要性优先，同档内新的先入选」，所以预算吃紧时被截掉的是
    /// 次要的、旧的条目；渲染时再按创建时间正序排，保证每次请求拼出来的字符串稳定。
    static func select(_ memories: [StoredMemory]) -> Selection {
        let candidates = memories
            .filter { $0.isEnabled }
            .filter { !$0.trimmedContent.isEmpty }
            .sorted(by: order)

        var selection = Selection()
        var used = 0
        for memory in candidates {
            let cost = memory.characterCount
            if used + cost > MemoryBudget.maxCharacters {
                selection.omitted.append(memory)
                continue
            }
            used += cost
            selection.included.append(memory)
        }
        return selection
    }

    /// 拼成一段文本；没有可用条目时返回 nil，调用方就不往 system 里加东西。
    static func section(_ memories: [StoredMemory]) -> String? {
        let selection = select(memories)
        guard !selection.included.isEmpty else { return nil }

        var parts: [String] = [header]

        for target in MemoryTarget.allCases {
            let group = selection.included
                .filter { $0.target == target }
                .sorted { $0.createdAt < $1.createdAt }
            guard !group.isEmpty else { continue }
            var lines: [String] = ["<memory target=\"\(target.rawValue)\">"]
            for memory in group {
                let prefix = memory.importance == .critical ? "- [重要] " : "- "
                lines.append(prefix + memory.trimmedContent)
            }
            lines.append("</memory>")
            parts.append(lines.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }

    /// 注入这段时实际占的字数，设置页显示用。
    static func characterCount(_ memories: [StoredMemory]) -> Int {
        section(memories)?.count ?? 0
    }

    /// 本次注入跳过了几条（超预算）。
    static func omittedCount(_ memories: [StoredMemory]) -> Int {
        select(memories).omitted.count
    }

    private static func order(_ a: StoredMemory, _ b: StoredMemory) -> Bool {
        if a.importance.rank != b.importance.rank {
            return a.importance.rank < b.importance.rank
        }
        if a.createdAt != b.createdAt {
            return a.createdAt > b.createdAt
        }
        return a.id.uuidString < b.id.uuidString
    }
}

// MARK: - 去重

/// 中文短句没有空格，用字符二元组算 Jaccard 比按词切分稳。
enum MemorySimilarity {

    static func score(_ a: String, _ b: String) -> Double {
        let left = bigrams(a)
        let right = bigrams(b)
        guard !left.isEmpty, !right.isEmpty else {
            return normalized(a) == normalized(b) ? 1 : 0
        }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    /// 返回与 `content` 最像的已有条目（相似度超过阈值）。
    static func duplicate(of content: String, in memories: [StoredMemory]) -> StoredMemory? {
        var best: (StoredMemory, Double)?
        for memory in memories {
            let value = score(content, memory.content)
            if value >= MemoryBudget.duplicateThreshold,
               best == nil || value > best!.1 {
                best = (memory, value)
            }
        }
        return best?.0
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func bigrams(_ text: String) -> Set<String> {
        let chars = Array(normalized(text))
        guard chars.count > 1 else {
            return chars.isEmpty ? [] : [String(chars)]
        }
        var set = Set<String>()
        for index in 0..<(chars.count - 1) {
            set.insert(String(chars[index...index + 1]))
        }
        return set
    }
}

// MARK: - 显式入口

/// 输入框里以「记住：」开头的整句话直接存成记忆，不发请求。
enum MemoryCommand {

    static let prefixes = ["记住：", "记住:", "记下：", "记下:", "remember:", "remember："]

    /// 命中返回要存的内容，否则 nil。只认明确的冒号前缀，避免把
    /// 「记住这个」这类正常对话误判成命令。
    static func payload(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in prefixes {
            guard trimmed.lowercased().hasPrefix(prefix.lowercased()) else { continue }
            let rest = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }
}
