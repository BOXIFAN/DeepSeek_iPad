import Foundation

/// 模型自己的硬参数。上下文窗口决定「剩余上下文」怎么算，放一处别散在视图里。
///
/// 两个模型都是 1M 上下文（见 docs/DEVELOPMENT.md §9 的 API 现状）。这里不做
/// 网络拉取：`/anthropic/v1/messages` 不返回窗口大小，拉不到时还得回退到这张表，
/// 多一条网络依赖只会多一个失败面。
enum ModelCatalog {

    static let flash = "deepseek-flash"
    static let pro = "deepseek-v4-pro"

    static let all: [String] = [flash, pro]

    /// 官方给的上下文窗口：1,000,000 tokens。
    static let defaultContextWindow = 1_000_000

    private static let windows: [String: Int] = [
        flash: 1_000_000,
        pro: 1_000_000
    ]

    static func contextWindow(for model: String) -> Int {
        windows[model] ?? defaultContextWindow
    }

    /// 顶栏与明细里用的短名。
    static func displayName(for model: String) -> String {
        model.isEmpty ? flash : model
    }
}
