import Foundation
import Network
import Observation

/// 余额的本地状态。全局一份，启动、回前台、网络恢复、发送结束、手动点刷新时更新。
///
/// 真机上「卡片总是显示失败、要手动刷新」的根因是调度只有启动和发送结束两个点：
/// 一次冷启动抢在网络就绪前、或者从后台回来时连接已失效，错误就停在卡片上，
/// 之后再也不会有请求。这里补上四件事：
/// 1. 失败后按 `BalanceRetryPolicy` 自动退避重试；
/// 2. 网络恢复（`NWPathMonitor`）时补一次；
/// 3. 每 3 分钟周期刷新；
/// 4. 有旧快照时失败不清空数字，只在副标题里说明「刷新失败 / 稍后重试」。
@Observable
@MainActor
final class BalanceStore {

    static let shared = BalanceStore()

    private(set) var snapshot: BalanceSnapshot?
    private(set) var isLoading = false
    private(set) var errorText: String?
    /// 错误是否值得自动重试（Key 无效、余额不足不重试）
    private(set) var errorIsRetryable = false
    private(set) var lastAttempt: Date?
    private(set) var consecutiveFailures = 0
    /// 下一次自动重试的时间点；退避期间普通刷新会跳过它，手动点仍然立即生效
    private(set) var nextRetryAt: Date?

    /// 低于这个额度就把卡片标成警示色。和 DeepSeek 控制台的充值提示阈值一致。
    static let lowThreshold: Double = 20
    /// 周期刷新间隔：余额不是实时数据，3 分钟够了。
    static let autoRefreshInterval: TimeInterval = 180

    private let client = BalanceClient()
    private var requestTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    /// 主动取消（删 Key、重启库）时让在途请求的结果作废
    private var generation = 0
    private var started = false
    private var monitor: NWPathMonitor?

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

    /// 卡片副标题：成功报时间，失败报原因，有旧数据时两者一起报。
    var note: String {
        guard hasKey else { return "还没填 API Key" }

        if isLoading {
            if let snapshot {
                return "\(Self.timeText(snapshot.fetchedAt)) 更新 · 查询中…"
            }
            return "查询中…"
        }

        if errorText != nil {
            if let snapshot {
                let tail = errorIsRetryable ? "稍后自动重试" : "刷新失败"
                return "\(Self.timeText(snapshot.fetchedAt)) 更新 · \(tail)"
            }
            if errorIsRetryable, consecutiveFailures > 0 {
                return "\(errorText ?? "查询失败")（第 \(consecutiveFailures) 次）"
            }
            return errorText ?? "查询失败"
        }

        if let snapshot {
            return "\(Self.timeText(snapshot.fetchedAt)) 更新"
        }
        return "点一下查询"
    }

    // MARK: - 生命周期

    /// 启动周期刷新与网络监听。幂等，视图重建时重复调用没有副作用。
    func start() {
        guard !started else { return }
        started = true
        startNetworkMonitor()
        startPeriodicRefresh()
    }

    private func startPeriodicRefresh() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.autoRefreshInterval))
                guard !Task.isCancelled else { return }
                self?.refreshIfStale(within: Self.autoRefreshInterval - 10)
            }
        }
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                self?.networkBecameAvailable()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.ruakiu.ipadds.balance-network"))
        self.monitor = monitor
    }

    /// 网络刚恢复：正在失败就立刻重试，成功过就走普通节流。
    func networkBecameAvailable() {
        if errorText != nil {
            refresh()
        } else {
            refreshIfStale(within: 20)
        }
    }

    // MARK: - 查询

    func refresh() {
        // 单飞：正在请求就不叠第二个，避免两个请求互相 cancel
        guard !isLoading else { return }
        guard let key = KeychainStore.read(), !key.isEmpty else {
            errorText = BalanceError.missingKey.errorDescription
            errorIsRetryable = false
            consecutiveFailures = 0
            return
        }

        retryTask?.cancel()
        retryTask = nil
        nextRetryAt = nil

        generation &+= 1
        let requestGeneration = generation
        isLoading = true
        errorText = nil
        lastAttempt = Date()

        requestTask = Task { [weak self] in
            guard let self else { return }
            let outcome: Result<BalanceSnapshot, Error>
            do {
                let result = try await self.client.fetch(apiKey: key)
                outcome = .success(result)
            } catch {
                outcome = .failure(error)
            }

            // 被 reset() / 新一轮请求作废时不改状态
            guard requestGeneration == self.generation else { return }
            self.isLoading = false

            switch outcome {
            case .success(let snapshot):
                self.snapshot = snapshot
                self.errorText = nil
                self.errorIsRetryable = false
                self.consecutiveFailures = 0
                self.nextRetryAt = nil
            case .failure(let error):
                self.handleFailure(error)
            }
        }
    }

    /// 距离上次成功查询不到 `seconds` 秒就不重复请求。
    func refreshIfStale(within seconds: TimeInterval = 60) {
        guard !isLoading else { return }
        if let fetched = snapshot?.fetchedAt,
           Date().timeIntervalSince(fetched) < seconds {
            return
        }
        // 已经在退避等待里就按退避表自己的节奏走，避免和周期刷新叠成连发
        if let nextRetryAt, nextRetryAt > Date(), errorText != nil {
            return
        }
        refresh()
    }

    private func handleFailure(_ error: Error) {
        // 主动取消（删 Key、切库）不算一次失败
        if case BalanceError.cancelled = error { return }

        consecutiveFailures += 1
        errorIsRetryable = BalanceRetryPolicy.isRetryable(error)
        errorText = Self.message(for: error)

        guard errorIsRetryable,
              let delay = BalanceRetryPolicy.delay(afterFailure: consecutiveFailures) else {
            nextRetryAt = nil
            return
        }
        scheduleRetry(after: delay)
    }

    private func scheduleRetry(after delay: TimeInterval) {
        retryTask?.cancel()
        nextRetryAt = Date().addingTimeInterval(delay)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.nextRetryAt = nil
            self.refresh()
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? BalanceError, let description = error.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private static func timeText(_ date: Date) -> String {
        hourFormatter.string(from: date)
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - 调试与重置

    /// 调试钩子：`DS_BALANCE_DEMO=1` 时用一份示例余额填卡片，命令行截图用。
    func applyDemoSnapshot() {
        generation &+= 1
        requestTask?.cancel()
        requestTask = nil
        retryTask?.cancel()
        retryTask = nil
        snapshot = BalanceSnapshot(
            isAvailable: true,
            infos: [BalanceInfo(currency: "CNY", total: "14.41", granted: "10.00", toppedUp: "4.41")],
            fetchedAt: Date()
        )
        errorText = nil
        errorIsRetryable = false
        isLoading = false
        consecutiveFailures = 0
        nextRetryAt = nil
        lastAttempt = Date()
    }

    func reset() {
        generation &+= 1
        requestTask?.cancel()
        requestTask = nil
        retryTask?.cancel()
        retryTask = nil
        snapshot = nil
        errorText = nil
        errorIsRetryable = false
        isLoading = false
        consecutiveFailures = 0
        nextRetryAt = nil
        lastAttempt = nil
    }
}
