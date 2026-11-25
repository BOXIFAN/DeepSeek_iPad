import Foundation

/// 会话级的用量视图。
///
/// 三个数字的口径：
/// - **已用上下文** = 最近一轮请求的输入（未命中 + 命中缓存 + 写入缓存）+ 这一轮的输出。
///   历史消息是全量回传的，所以最后一轮的输入就是整段会话的上下文占用。
/// - **缓存命中** = 最近一轮里 `cacheReadTokens / 总输入`。
/// - **tok/s** = 最近一轮输出 token ÷ 首个 token 到结束的耗时。
struct SessionMetrics: Equatable, Sendable {

    var model: String = ModelCatalog.flash
    var contextWindow: Int = ModelCatalog.defaultContextWindow
    /// 最近一轮成功后占用的上下文 token
    var usedTokens: Int = 0
    var lastUsage: Usage? = nil
    var tokensPerSecond: Double? = nil

    // MARK: - 派生值

    var remainingTokens: Int {
        max(contextWindow - usedTokens, 0)
    }

    var remainingRatio: Double {
        guard contextWindow > 0 else { return 0 }
        return Double(remainingTokens) / Double(contextWindow)
    }

    /// 剩余不到 15% 就该提示新建会话了。
    var isNearLimit: Bool {
        remainingRatio < 0.15
    }

    var isOverLimit: Bool {
        usedTokens >= contextWindow
    }

    var cacheHitRate: Double? {
        lastUsage?.cacheHitRate
    }

    var hasRoundUsage: Bool {
        guard let lastUsage else { return false }
        return lastUsage.totalTokens > 0
    }

    // MARK: - 更新

    mutating func reset(for model: String) {
        self.model = model
        contextWindow = ModelCatalog.contextWindow(for: model)
        usedTokens = 0
        lastUsage = nil
        tokensPerSecond = nil
    }

    /// 用一轮成功的用量覆盖。空 usage（缺字段）不覆盖已有数字，避免一次异常把卡片清空。
    mutating func apply(_ usage: Usage, model: String?, tokensPerSecond: Double?) {
        if let model, !model.isEmpty {
            self.model = model
            contextWindow = ModelCatalog.contextWindow(for: model)
        }
        guard usage.totalTokens > 0 else { return }
        lastUsage = usage
        usedTokens = usage.totalInputTokens + usage.outputTokens
        self.tokensPerSecond = tokensPerSecond
    }

    // MARK: - 格式化（自检也走这里，保证界面与测试同一套口径）

    static func tokenText(_ count: Int) -> String {
        let value = max(count, 0)
        if value < 1_000 { return "\(value)" }
        if value < 1_000_000 {
            let k = Double(value) / 1_000
            return k < 10
                ? String(format: "%.1fK", k)
                : String(format: "%.0fK", k)
        }
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }

    static func cacheText(_ rate: Double?) -> String? {
        guard let rate, rate.isFinite else { return nil }
        return String(format: "%.0f%%", max(0, min(1, rate)) * 100)
    }

    static func rateText(_ tokensPerSecond: Double?) -> String? {
        guard let tokensPerSecond, tokensPerSecond > 0, tokensPerSecond.isFinite else { return nil }
        return tokensPerSecond < 10
            ? String(format: "%.1f tok/s", tokensPerSecond)
            : String(format: "%.0f tok/s", tokensPerSecond)
    }

    /// 流式过程中没有 usage，用字符数粗估输出 token。
    /// 英文约 4 字符 / token，中文约 1.5–2 字符 / token，混排取 2.6。
    static func estimatedTokens(forCharacters count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(1, Int((Double(count) / 2.6).rounded()))
    }
}
