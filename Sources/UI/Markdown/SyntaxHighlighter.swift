import SwiftUI

/// 轻量语法高亮。
///
/// 只用正则做四类着色（关键字、数字、字符串、注释），按 One Dark 的色板取值，
/// 深色浅色都能看。
///
/// 规则的应用顺序决定覆盖关系（后应用的覆盖先应用的）：
/// 关键字 → 数字 → 单行注释 → 多行注释 → 字符串。
/// 字符串放最后，这样 `"https://..."` 里的 `//` 不会被误判成注释。
enum SyntaxHighlighter {

    private struct Rule {
        let pattern: String
        let color: Color
    }

    private static let keywordColor = Color(red: 0.78, green: 0.47, blue: 0.87)
    private static let numberColor = Color(red: 0.82, green: 0.60, blue: 0.40)
    private static let stringColor = Color(red: 0.60, green: 0.76, blue: 0.47)
    private static let commentColor = Color(red: 0.50, green: 0.52, blue: 0.56)

    static func highlight(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.font = .system(.callout, design: .monospaced)
        attributed.foregroundColor = .primary

        for rule in rules(for: (language ?? "").lowercased()) {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.anchorsMatchLines]) else {
                continue
            }
            let fullRange = NSRange(code.startIndex..<code.endIndex, in: code)
            regex.enumerateMatches(in: code, options: [], range: fullRange) { match, _, _ in
                guard let match,
                      let sourceRange = Range(match.range, in: code),
                      let lower = AttributedString.Index(sourceRange.lowerBound, within: attributed),
                      let upper = AttributedString.Index(sourceRange.upperBound, within: attributed) else {
                    return
                }
                attributed[lower..<upper].foregroundColor = rule.color
            }
        }
        return attributed
    }

    private static func rules(for language: String) -> [Rule] {
        let keyword: String
        let lineComment: String

        switch language {
        case "swift":
            keyword = #"\b(func|let|var|if|else|guard|return|struct|class|enum|protocol|extension|import|for|in|while|switch|case|default|throw|throws|try|async|await|actor|public|private|internal|static|init|self|nil|true|false|some|any)\b"#
            lineComment = #"//.*$"#

        case "python", "py":
            keyword = #"\b(def|class|if|elif|else|return|import|from|as|for|in|while|with|try|except|finally|raise|lambda|None|True|False|and|or|not|async|await|yield|global|pass)\b"#
            lineComment = #"#.*$"#

        case "javascript", "js", "typescript", "ts":
            keyword = #"\b(const|let|var|function|return|if|else|for|while|class|new|import|export|default|async|await|try|catch|finally|throw|typeof|null|undefined|true|false|this)\b"#
            lineComment = #"//.*$"#

        case "json":
            // 键名着色即可，JSON 没有关键字和注释
            keyword = #""[^"]*"(?=\s*:)"#
            lineComment = #"(?!)"#

        case "bash", "sh", "shell", "zsh":
            keyword = #"\b(if|then|else|fi|for|in|do|done|while|case|esac|function|return|export|local|echo|cd|mkdir|rm|cp|mv|curl|git|sudo)\b"#
            lineComment = #"#.*$"#

        default:
            keyword = #"(?!)"#
            lineComment = #"(?!)"#
        }

        return [
            Rule(pattern: keyword, color: keywordColor),
            Rule(pattern: #"\b\d+(\.\d+)?\b"#, color: numberColor),
            Rule(pattern: lineComment, color: commentColor),
            Rule(pattern: #"/\*[\s\S]*?\*/"#, color: commentColor),
            Rule(pattern: "\"([^\"\\\\]|\\\\.)*\"", color: stringColor),
            Rule(pattern: "'([^'\\\\]|\\\\.)*'", color: stringColor)
        ]
    }
}
