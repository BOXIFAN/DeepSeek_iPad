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

    var primary: BalanceInfo? { infos.first }
}

enum BalanceError: LocalizedError {
    case missingKey
    case http(Int)
    case format
    case offline

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
        case .format:
            return "余额响应格式不对"
        case .offline:
            return "网络不通，稍后再试"
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
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet || error.code == .cannotConnectToHost
                ? BalanceError.offline
                : BalanceError.http(error.code.rawValue)
        }

        guard let http = response as? HTTPURLResponse else { throw BalanceError.format }
        guard (200..<300).contains(http.statusCode) else {
            throw BalanceError.http(http.statusCode)
        }
        return try Self.decode(data)
    }
}
