import Foundation
import SwiftData

// MARK: - 内置技能

/// 随 App 发布的两个技能。首次启动装进本地库，默认不启用——
/// 用不用由输入条上的技能胶囊决定，不做全局常驻注入。
/// 删掉后可以在技能页右上角菜单里恢复。
enum BuiltinSkills {

    /// 改内容时把版本号 +1，升级后会给还没装过的用户补装一次。
    static let version = 1

    struct Definition {
        let name: String
        let summary: String
        let instructions: String
    }

    static let all: [Definition] = [
        Definition(
            name: "结论先行",
            summary: "第一句给结论，依据最多三条",
            instructions: """
            每次回答先给结论，再给依据。

            - 第一句话就是结论，不要用「这个问题可以从几个方面看」这类铺垫。
            - 结论里有数字就给数字，没有数字就说清判断的前提。
            - 依据按重要性排，最多三条；超过三条的收进表格或列表。
            - 不确定的地方直接标出来，不要用「可能」「一般来说」含糊带过。
            """
        ),
        Definition(
            name: "术语注解",
            summary: "英文术语首次出现时给中文对照",
            instructions: """
            回答里出现英文术语时，第一次出现用「英文（中文）」的形式，之后直接用英文。

            - 缩写第一次出现要展开：SSE（Server-Sent Events，服务端推送事件）。
            - 有公认中文译名的用译名，没有的保留英文，不要硬造。
            - 代码、命令、API 字段名不翻译。
            - 同一段落内不重复注解。
            """
        )
    ]
}

// MARK: - 安装

@MainActor
enum SkillInstaller {

    private static let versionKey = "builtinSkillsVersion"

    private static var isMemoryStore: Bool {
        ProcessInfo.processInfo.environment["DS_MEMORY_STORE"] == "1"
    }

    /// 正常启动：只在版本号落后时装一次，用户删掉的不会自己回来。
    /// `force` 用于技能页的「恢复内置技能」，把缺的名补上。
    static func installMissing(force: Bool = false) {
        let context = ConversationStore.shared.context
        let stored = (try? context.fetch(FetchDescriptor<StoredSkill>())) ?? []
        let names = Set(stored.map(\.name))

        let installedVersion = isMemoryStore ? 0 : UserDefaults.standard.integer(forKey: versionKey)
        let shouldRun = force || isMemoryStore || installedVersion < BuiltinSkills.version
        guard shouldRun else { return }

        var inserted = 0
        for definition in BuiltinSkills.all where !names.contains(definition.name) {
            let skill = StoredSkill(
                name: definition.name,
                summary: definition.summary,
                instructions: definition.instructions,
                isEnabled: false
            )
            context.insert(skill)
            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
        }

        if !isMemoryStore {
            UserDefaults.standard.set(BuiltinSkills.version, forKey: versionKey)
        }
    }

    /// 技能页里判断哪些条目是内置的，用来显示标记。
    static func isBuiltin(_ skill: StoredSkill) -> Bool {
        BuiltinSkills.all.contains { $0.name == skill.name }
    }
}
