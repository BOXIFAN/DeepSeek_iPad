import Foundation
import UniformTypeIdentifiers

// MARK: - 解析方式

/// `POST /files` 的 `purpose`。
///
/// - `user_data`：纯文本、代码、CSV/JSON、XLSX、EPUB 这类不需要解析的文件，不计费。
/// - `text_recognition`：PDF / Word / PowerPoint，只把文字交给模型，文档里的图丢弃。
/// - `rich_layout_recognition`：文字 + 按原位置裁出的图，占输入 token，按页计费更贵。
enum DocumentPurpose: String, Codable, Sendable {
    case userData = "user_data"
    case textRecognition = "text_recognition"
    case richLayoutRecognition = "rich_layout_recognition"

    var title: String {
        switch self {
        case .userData: return "直接读取"
        case .textRecognition: return "解析文字"
        case .richLayoutRecognition: return "解析文字与图表"
        }
    }
}

// MARK: - 类型判定

enum DocumentKind: String, Sendable {
    /// PDF / Word / PowerPoint，上传时解析
    case parsed
    /// 文本、代码、表格、电子书，上传后直接引用（不计费）
    case data

    static let maxPerMessage = 5
    static let maxParsedBytes = 100 * 1024 * 1024
    static let maxDataBytes = 32 * 1024 * 1024

    private static let parsedExtensions: Set<String> = ["pdf", "doc", "docx", "ppt", "pptx"]

    /// UTType 不一定认的（代码/配置/表格/电子书），显式列出来，剩下的再交给 UTType 兜底。
    private static let dataExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "mdown", "csv", "tsv", "json", "jsonl", "ndjson",
        "xml", "yaml", "yml", "toml", "ini", "conf", "cfg", "log", "tex", "plist",
        "html", "htm", "css", "scss", "less", "js", "mjs", "cjs", "jsx", "ts", "tsx",
        "swift", "py", "pyw", "java", "kt", "kts", "c", "h", "cc", "cpp", "cxx", "hpp",
        "m", "mm", "go", "rs", "rb", "php", "sh", "bash", "zsh", "fish", "ps1",
        "sql", "r", "scala", "lua", "vue", "svelte", "dart", "cs", "vb", "asm",
        "gradle", "properties", "env", "gitignore", "dockerfile", "makefile",
        "xlsx", "xls", "epub", "mobi"
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp"
    ]

    static func kind(for url: URL) -> DocumentKind? {
        let ext = url.pathExtension.lowercased()
        if parsedExtensions.contains(ext) { return .parsed }
        if dataExtensions.contains(ext) { return .data }
        if ext.isEmpty {
            let name = url.lastPathComponent.lowercased()
            return ["makefile", "dockerfile", "readme", "license"].contains(name) ? .data : nil
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .text) {
            return .data
        }
        return nil
    }

    static func isImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    static func purpose(for kind: DocumentKind, keepLayout: Bool) -> DocumentPurpose {
        switch kind {
        case .data:
            return .userData
        case .parsed:
            return keepLayout ? .richLayoutRecognition : .textRecognition
        }
    }

    static func maxBytes(for kind: DocumentKind) -> Int {
        kind == .parsed ? maxParsedBytes : maxDataBytes
    }

    /// 选择器直接放开到所有文件，选完再按扩展名过滤。
    /// 用 UTType 白名单做 `allowedContentTypes` 会在代码文件、Markdown 上漏类型。
    static var allowedTypes: [UTType] { [.item] }
}

// MARK: - 已上传的文档

struct MessageDocument: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    /// 服务端返回的 `file-api-...`
    var fileID: String
    var filename: String
    var byteCount: Int
    var purpose: DocumentPurpose

    init(id: UUID = UUID(),
         fileID: String,
         filename: String,
         byteCount: Int,
         purpose: DocumentPurpose) {
        self.id = id
        self.fileID = fileID
        self.filename = filename
        self.byteCount = byteCount
        self.purpose = purpose
    }

    /// 协议块。只放 `file_id`，文件名这类展示信息落库时另存。
    var blockJSON: [String: Any] {
        [
            "type": "document",
            "source": [
                "type": "file",
                "file_id": fileID
            ]
        ]
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var iconName: String {
        switch filename.lowercased().split(separator: ".").last {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "xls", "xlsx", "csv": return "tablecells"
        case "epub", "mobi": return "book"
        default: return "doc.plaintext"
        }
    }
}

// MARK: - 待发文档

/// 输入条里的待发文件。上传中、已就绪、失败三种状态，失败保留数据可直接重试。
struct PendingDocument: Identifiable {
    enum Phase {
        case uploading
        case ready(MessageDocument)
        case failed(String)
    }

    let id = UUID()
    var filename: String
    var byteCount: Int
    var kind: DocumentKind
    var purpose: DocumentPurpose
    var data: Data
    var phase: Phase = .uploading

    var isUploading: Bool {
        if case .uploading = phase { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    var document: MessageDocument? {
        if case .ready(let document) = phase { return document }
        return nil
    }

    var errorText: String? {
        if case .failed(let text) = phase { return text }
        return nil
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
