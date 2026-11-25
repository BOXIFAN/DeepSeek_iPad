import Foundation

/// 余额查询的失败重试策略。
///
/// 真机上「卡片一直显示失败」的主因是失败后没有任何重试：一次冷启动抢在网络就绪前，
/// 或者从后台回来时连接已经烂掉，错误就停在卡片上直到手动点。这里把退避表抽成纯函数，
/// 既方便自检，也避免策略散在 store 里改一处漏一处。
enum BalanceRetryPolicy {

    /// 第 1 次失败后等 5 秒，然后 15 / 45 / 120 秒。四次用完不再自动重试，
    /// 等回前台或网络恢复再补。
    static let delays: [TimeInterval] = [5, 15, 45, 120]

    /// - Parameter attempt: 连续失败次数，从 1 开始。
    /// - Returns: 下一次重试前的等待秒数；`nil` 表示不再自动重试。
    static func delay(afterFailure attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= delays.count else { return nil }
        return delays[attempt - 1]
    }

    /// 401/403（Key 无效）、402（余额不足）、4xx 参数类错误重试也变不出来，直接停；
    /// 429 与网络类错误等一等有意义。
    static func isRetryable(_ error: Error) -> Bool {
        guard let error = error as? BalanceError else { return true }
        switch error {
        case .missingKey, .format, .cancelled:
            return false
        case .timeout, .offline, .network:
            return true
        case .http(let code):
            if code == 429 { return true }
            return !(400..<500).contains(code)
        }
    }
}
