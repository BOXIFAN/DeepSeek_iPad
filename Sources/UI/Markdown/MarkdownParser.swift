import SwiftUI

/// 块级 Markdown 元素。
///
/// `Text(AttributedString(markdown:))` 只处理行内样式，代码块、表格、列表缩进都会退化，
/// 所以块级结构自己解析，行内样式交给 AttributedString。
enum MDBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case code(language: String?, code: String)
    case table(headers: [String], rows: [[String]])
    case bullets(items: [String])
    case numbered(items: [String])
    case quote(text: String)
    case divider
}

enum MarkdownParser {

    static func parse(_ source: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = source.components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(text: joined))
            }
            paragraph.removeAll()
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // 代码围栏
            if line.hasPrefix("```") {
                flushParagraph()
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if current.hasPrefix("```") {
                        index += 1
                        break
                    }
                    body.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language,
                                    code: body.joined(separator: "\n")))
                continue
            }

            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            // 分割线
            if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            // 标题
            if let heading = parseHeading(line) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            // 表格：本行以 | 开头，且下一行是分隔行
            if line.hasPrefix("|"), index + 1 < lines.count,
               isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let headers = splitRow(line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|") else { break }
                    rows.append(splitRow(row))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // 引用
            if line.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quote.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(text: quote.joined(separator: "\n")))
                continue
            }

            // 无序列表
            if let first = parseBullet(line) {
                flushParagraph()
                var items: [String] = [first]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if let item = parseBullet(current) {
                        items.append(item)
                        index += 1
                    } else if !current.isEmpty, lines[index].hasPrefix("  ") || lines[index].hasPrefix("\t") {
                        items[items.count - 1] += " " + current
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bullets(items: items))
                continue
            }

            // 有序列表
            if let first = parseOrdered(line) {
                flushParagraph()
                var items: [String] = [first]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if let item = parseOrdered(current) {
                        items.append(item)
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.numbered(items: items))
                continue
            }

            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    // MARK: - 行解析工具

    private static func parseHeading(_ line: String) -> MDBlock? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        return .heading(level: level, text: String(rest.dropFirst()))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        let stripped = trimmed
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
        return stripped.isEmpty
    }

    private static func splitRow(_ line: String) -> [String] {
        var content = line
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func parseBullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func parseOrdered(_ line: String) -> String? {
        var cursor = line.startIndex
        var digits = ""
        while cursor < line.endIndex, line[cursor].isNumber {
            digits.append(line[cursor])
            cursor = line.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < line.endIndex, line[cursor] == "." else { return nil }
        let afterDot = line.index(after: cursor)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...])
    }
}
