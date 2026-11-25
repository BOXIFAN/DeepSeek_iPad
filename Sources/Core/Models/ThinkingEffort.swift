import Foundation

/// 思考强度。DeepSeek 的 Anthropic 兼容接口用 `output_config.effort` 控制，
/// 取值 low / high / max；关闭思考时不发这个字段。
enum ThinkingEffort: String, CaseIterable, Identifiable {
    case off
    case low
    case standard
    case high

    var id: String { rawValue }

    /// 界面上显示的名字。
    var title: String {
        switch self {
        case .off: return "关闭"
        case .low: return "低"
        case .standard: return "标准"
        case .high: return "高"
        }
    }

    /// 菜单里的补充说明，只在设置页用。
    var detail: String {
        switch self {
        case .off: return "不输出思维链"
        case .low: return "想得短"
        case .standard: return "默认"
        case .high: return "想得最久"
        }
    }

    /// 发给 API 的 effort 值；关闭时为 nil。
    var apiValue: String? {
        switch self {
        case .off: return nil
        case .low: return "low"
        case .standard: return "high"
        case .high: return "max"
        }
    }

    var isEnabled: Bool { self != .off }

    static let storageKey = "thinkingEffort"

    /// 存进 UserDefaults 的原始值，读不出来就回到标准档。
    static var stored: ThinkingEffort {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ThinkingEffort.standard.rawValue
        return ThinkingEffort(rawValue: raw) ?? .standard
    }
}
