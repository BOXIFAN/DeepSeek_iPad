import Foundation

// MARK: - 模型

/// `GET /user/balance` 里的单条余额记录。金额是字符串，官方按币种分别返回。
struct BalanceInfo: Sendable, Equatable {
    var currency: String
    var total: String
    var granted: String?
    var toppedUp: String?

    var totalValue: Double { Double(total) ?? 0 }

    var symbol: String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "CNY", "RMB": return "¥"
        default: return "\(currency) "
        }
    }
}

struct BalanceSnapshot: Sendable, Equatable {
    var isAvailable: Bool
    var infos: [BalanceInfo]
    var fetchedAt: Date

    /// 官方会同时返回 USD 和 CNY 两条，金额为 0 的那条也照样返回。
    /// 直接取第一条会把 `$0.00` 显示在卡片上，所以优先挑有余额的币种。
    var primary: BalanceInfo? {
        if let positive = infos.first(where: { $0.totalValue > 0 }) {
            return positive
        }
        if let cny = infos.first(where: { $0.currency.uppercased() == "CNY" }) {
            return cny
        }
        return infos.first
    }
}

enum BalanceError: LocalizedError {
    case missingKey
    case http(Int)
    case timeout
    case offline
    case cancelled
    case network(Int)
    case format

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "还没填 API Key"
        case .http(let code):
            switch code {
            case 401, 403:
                return "API Key 无效或没有查询权限"
            case 402:
                return "账户余额不足"
            case 429:
                return "查询太频繁，稍后再试"
            default:
                return "查询失败（HTTP \(code)）"
            }
        case .timeout:
            return "查询超时，点一下重试"
        case .offline:
            return "网络不通，稍后再试"
        case .cancelled:
            return "查询已取消"
        case .network(let code):
            return "网络错误（\(code)）"
        case .format:
            return "余额响应格式不对"
        }
    }
}

// MARK: - 客户端

/// 余额查询走 `GET https://api.deepseek.com/user/balance`，鉴权是 `Bearer`。
/// 和聊天用的 `x-api-key` 不是同一个头，别混。
final class BalanceClient {

    private let endpoint: URL
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        // 真机上从后台回来时网络栈要几秒才恢复：等它，不要立刻判失败
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        config.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: config)
        endpoint = Self.endpoint()
    }

    /// 和 ChatClient 共用 `DS_API_BASE`，mock 时两处一起指过去。
    static func endpoint() -> URL {
        if let base = ProcessInfo.processInfo.environment["DS_API_BASE"],
           !base.isEmpty,
           let url = URL(string: base.trimmingCharacters(in: .whitespaces)) {
            return url.appendingPathComponent("user/balance")
        }
        return URL(string: "https://api.deepseek.com/user/balance")!
    }

    static func decode(_ data: Data) throws -> BalanceSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BalanceError.format
        }
        let isAvailable = json["is_available"] as? Bool ?? false
        let raw = json["balance_infos"] as? [[String: Any]] ?? []
        let infos = raw.map { dict in
            BalanceInfo(
                currency: dict["currency"] as? String ?? "CNY",
                total: dict["total_balance"] as? String ?? "0",
                granted: dict["granted_balance"] as? String,
                toppedUp: dict["topped_up_balance"] as? String
            )
        }
        return BalanceSnapshot(isAvailable: isAvailable, infos: infos, fetchedAt: Date())
    }

    func fetch(apiKey: String) async throws -> BalanceSnapshot {
        guard !apiKey.isEmpty else { throw BalanceError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 余额是账户数据，既不吃本地缓存，也不让中间代理缓存住
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 25

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .cannotConnectToHost,
                 .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw BalanceError.offline
            case .timedOut:
                throw BalanceError.timeout
            case .cancelled:
                throw BalanceError.cancelled
            default:
                throw BalanceError.network(error.code.rawValue)
            }
        } catch is CancellationError {
            throw BalanceError.cancelled
        }

        guard let http = response as? HTTPURLResponse else { throw BalanceError.format }
        guard (200..<300).contains(http.statusCode) else {
            throw BalanceError.http(http.statusCode)
        }
        return try Self.decode(data)
    }
}
