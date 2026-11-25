import Foundation

// MARK: - 错误

enum DocumentError: LocalizedError {
    case missingKey
    case unsupported(String)
    case tooLarge(String, Int)
    case unreadable(String)
    case timeout
    case offline
    case cancelled
    case http(Int, String)
    case format

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "还没填 API Key"
        case .unsupported(let name):
            return "不支持读取 \(name)"
        case .tooLarge(let name, let limit):
            let size = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            return "\(name) 超过 \(size) 上限"
        case .unreadable(let name):
            return "读不了 \(name)，可能没有访问权限"
        case .timeout:
            return "上传或解析超时，换小一点的文件再试"
        case .offline:
            return "网络不通，稍后重试"
        case .cancelled:
            return "上传已取消"
        case .http(let code, let detail):
            switch code {
            case 400:
                return detail.isEmpty
                    ? "文件打不开或格式不支持（带密码的文档也会被拒）"
                    : "文件无法解析：\(detail)"
            case 408:
                return "上传超时（需在 120 秒内传完）"
            case 413:
                return "文件超过服务端大小上限"
            case 429:
                return "同时解析的文档太多，等一会再试"
            case 500:
                return "文档解析结果不完整，重试一次"
            case 503:
                return "文档解析服务繁忙，稍后重试"
            case 504:
                return "解析超过 120 秒，换小一点的文档"
            default:
                return detail.isEmpty ? "上传失败（HTTP \(code)）" : "HTTP \(code)：\(detail)"
            }
        case .format:
            return "上传响应格式不对"
        }
    }
}

// MARK: - 上传

/// 文件统一走 `POST /files` 拿 `file_id`，对话里再用 `document` 块引用。
///
/// 两个硬约束来自官方文档：
/// 1. multipart 里 `purpose` 必须排在 `file` 之前，否则 400。
/// 2. 解析在上传过程中完成，响应要等解析结束才回，超时按「上传 120s + 解析 120s」放宽。
final class FileUploader {

    static let shared = FileUploader()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    /// 和聊天、余额共用 `DS_API_BASE`。
    static func endpoint() -> URL {
        if let base = ProcessInfo.processInfo.environment["DS_API_BASE"],
           !base.isEmpty,
           let url = URL(string: base.trimmingCharacters(in: .whitespaces)) {
            return url.appendingPathComponent("files")
        }
        return URL(string: "https://api.deepseek.com/files")!
    }

    // MARK: - 请求体

    /// 手写 multipart。字段顺序就是协议要求：`purpose` → `file`。
    static func multipartBody(boundary: String,
                              filename: String,
                              purpose: DocumentPurpose,
                              data: Data) -> Data {
        var body = Data()
        func append(_ text: String) {
            body.append(Data(text.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        append("\(purpose.rawValue)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename(filename))\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }

    /// 文件名直接放 UTF-8，只去掉会破坏 header 的引号与换行；服务端上限 512 字节。
    static func safeFilename(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "file" }
        while cleaned.utf8.count > 480 {
            cleaned.removeLast()
        }
        return cleaned
    }

    // MARK: - 响应

    static func decode(_ data: Data,
                       fallbackFilename: String,
                       requestedPurpose: DocumentPurpose) throws -> MessageDocument {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String, !id.isEmpty else {
            throw DocumentError.format
        }
        let name = (json["filename"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackFilename
        let bytes = (json["bytes"] as? Int) ?? (json["size_bytes"] as? Int) ?? 0
        let purpose = (json["purpose"] as? String)
            .flatMap(DocumentPurpose.init(rawValue:)) ?? requestedPurpose
        return MessageDocument(fileID: id,
                               filename: name,
                               byteCount: bytes,
                               purpose: purpose)
    }

    // MARK: - 上传

    func upload(data: Data,
                filename: String,
                purpose: DocumentPurpose,
                apiKey: String) async throws -> MessageDocument {
        guard !apiKey.isEmpty else { throw DocumentError.missingKey }

        let boundary = "----iPadDS-\(UUID().uuidString)"
        let body = Self.multipartBody(boundary: boundary,
                                      filename: filename,
                                      purpose: purpose,
                                      data: data)

        var request = URLRequest(url: Self.endpoint())
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        request.timeoutInterval = 180

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost, .dataNotAllowed:
                throw DocumentError.offline
            case .timedOut:
                throw DocumentError.timeout
            case .cancelled:
                throw DocumentError.cancelled
            default:
                throw DocumentError.http(error.code.rawValue, error.localizedDescription)
            }
        } catch is CancellationError {
            throw DocumentError.cancelled
        }

        guard let http = response as? HTTPURLResponse else { throw DocumentError.format }
        guard (200..<300).contains(http.statusCode) else {
            throw DocumentError.http(http.statusCode, Self.errorMessage(from: responseData))
        }
        return try Self.decode(responseData,
                               fallbackFilename: filename,
                               requestedPurpose: purpose)
    }

    /// 兼容 `{"error":{"message":…}}` 与 `{"message":…}`。
    static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(200)
                .description
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return ""
    }
}
