import Foundation
import Observation

/// 余额的本地状态。全局一份，启动、发送结束、手动点刷新时更新。
@Observable
@MainActor
final class BalanceStore {

    static let shared = BalanceStore()

    private(set) var snapshot: BalanceSnapshot?
    private(set) var isLoading = false
    private(set) var errorText: String?
    private(set) var lastAttempt: Date?

    /// 低于这个额度就把卡片标成警示色。和 DeepSeek 控制台的充值提示阈值一致。
    static let lowThreshold: Double = 20

    private let client = BalanceClient()
    private var task: Task<Void, Never>?

    var hasKey: Bool { KeychainStore.hasAPIKey }

    var amountText: String {
        guard let info = snapshot?.primary else { return "—" }
        return info.symbol + info.total
    }

    var detailText: String? {
        guard let info = snapshot?.primary else { return nil }
        if let granted = info.granted, let topped = info.toppedUp {
            return "赠送 \(granted) · 充值 \(topped)"
        }
        return nil
    }

    var isLow: Bool {
        guard let value = snapshot?.primary?.totalValue else { return false }
        return value < Self.lowThreshold
    }

    /// 卡片副标题：有结果就报余额状态，没结果时报原因。
    var note: String {
        if let errorText { return errorText }
        if let snapshot {
            if isLow { return "低于 ¥\(Int(Self.lowThreshold))，记得充" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "刷新于 \(formatter.string(from: snapshot.fetchedAt))"
        }
        if !hasKey { return "还没填 API Key" }
        if isLoading { return "查询中…" }
        return "点一下查询"
    }

    func refresh() {
        guard !isLoading else { return }
        guard let key = KeychainStore.read(), !key.isEmpty else {
            errorText = BalanceError.missingKey.errorDescription
            return
        }

        isLoading = true
        errorText = nil
        lastAttempt = Date()
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                let result = try await self.client.fetch(apiKey: key)
                self.snapshot = result
                self.errorText = nil
            } catch {
                self.errorText = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    /// 距离上次成功查询不到 60 秒就不重复请求。
    func refreshIfStale(within seconds: TimeInterval = 60) {
        if isLoading { return }
        if let fetched = snapshot?.fetchedAt,
           Date().timeIntervalSince(fetched) < seconds {
            return
        }
        refresh()
    }

    /// 调试钩子：`DS_BALANCE_DEMO=1` 时用一份示例余额填卡片，命令行截图用。
    func applyDemoSnapshot() {
        snapshot = BalanceSnapshot(
            isAvailable: true,
            infos: [BalanceInfo(currency: "CNY", total: "14.41", granted: "10.00", toppedUp: "4.41")],
            fetchedAt: Date()
        )
        errorText = nil
    }

    func reset() {
        task?.cancel()
        snapshot = nil
        errorText = nil
        isLoading = false
    }
}
