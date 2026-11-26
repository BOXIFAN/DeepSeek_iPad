import Foundation
import SwiftData

// MARK: - 技能

/// 本地技能。技能在 App 里只承担「一段可复用的指令」，随请求注入到 system，
/// 不执行脚本，也不带资源目录。
@Model
final class StoredSkill {

    @Attribute(.unique) var id: UUID
    var name: String
    /// 一句话说明，列表里显示
    var summary: String
    /// 注入 system 的正文
    var instructions: String
    var isEnabled: Bool
    /// 从 Markdown 文件导入的标记，手动新建为 false
    var imported: Bool
    var createdAt: Date
    var updatedAt: Date

    init(name: String,
         summary: String = "",
         instructions: String = "",
         isEnabled: Bool = true,
         imported: Bool = false) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.instructions = instructions
        self.isEnabled = isEnabled
        self.imported = imported
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var characterCount: Int {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
}

// MARK: - 导入解析

/// 从 SKILL.md 这类文件里拆 YAML frontmatter，取 `name` 与 `description`，
/// 剩下的正文当作指令。解析失败不报错，退回文件名 + 全文。
enum SkillParser {

    struct Draft {
        var name: String
        var summary: String
        var instructions: String
    }

    static func parse(markdown: String, fallbackName: String) -> Draft {
        var text = markdown
        var name = fallbackName
        var summary = ""

        if text.hasPrefix("---") {
            let rest = text.dropFirst(3)
            if let close = rest.range(of: "\n---") {
                let header = rest[rest.startIndex..<close.lowerBound]
                text = String(rest[close.upperBound...])

                for line in header.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
                    var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if value.count >= 2,
                       (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                       (value.hasPrefix("'") && value.hasSuffix("'")) {
                        value = String(value.dropFirst().dropLast())
                    }
                    switch key {
                    case "name": name = value
                    case "description", "summary": summary = value
                    default: break
                    }
                }
            }
        }

        return Draft(
            name: name.isEmpty ? fallbackName : name,
            summary: summary,
            instructions: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - 组装 system

enum PromptComposer {

    /// 默认提示词在前，启用的技能按创建顺序居中，长期记忆放最后。
    ///
    /// 记忆放在最末是有意的：它更新频率比提示词和技能高，放在结尾能让前面的内容
    /// 保持稳定，服务端的上下文缓存至少能命中前缀。
    static func system(defaultPrompt: String,
                       skills: [StoredSkill],
                       memories: [StoredMemory] = []) -> String? {
        var parts: [String] = []

        let base = defaultPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty {
            parts.append(base)
        }

        for skill in skills where skill.isEnabled {
            let body = skill.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            parts.append("# 技能：\(skill.name)\n\n\(body)")
        }

        if let memorySection = MemoryComposer.section(memories) {
            parts.append(memorySection)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n---\n\n")
    }

    /// 设置页里给一行摘要用。
    static func characterCount(defaultPrompt: String,
                               skills: [StoredSkill],
                               memories: [StoredMemory] = []) -> Int {
        system(defaultPrompt: defaultPrompt, skills: skills, memories: memories)?.count ?? 0
    }
}
