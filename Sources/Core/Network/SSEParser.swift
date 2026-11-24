import Foundation

/// 一行 SSE 解析结果。
struct SSEEvent: Equatable {
    let name: String
    let data: String
}

/// Server-Sent Events 解析器。
///
/// 按行喂入，遇到空行时把攒下的 `event:` 与 `data:` 组装成一个事件返回。
/// 以下三种行要特殊处理：
///   - `:` 开头是注释，DeepSeek 用它发 keep-alive，直接忽略
///   - `event:` 记录事件名，可能出现在任何 data 行之前
///   - `data:` 可以出现多次，按 SSE 规范用换行拼接
struct SSEParser {

    private var eventName = ""
    private var dataLines: [String] = []
    private var sawAnything = false

    /// 喂一行（不含行尾换行符）。返回完整事件，或 nil 表示还没攒够。
    mutating func consume(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            guard sawAnything else { return nil }
            defer {
                eventName = ""
                dataLines = []
                sawAnything = false
            }
            return SSEEvent(
                name: eventName.isEmpty ? "message" : eventName,
                data: dataLines.joined(separator: "\n")
            )
        }

        if line.hasPrefix(":") {
            return nil
        }

        sawAnything = true

        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            // 规范里冒号后若有单个空格应去掉
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
        }

        return nil
    }
}
