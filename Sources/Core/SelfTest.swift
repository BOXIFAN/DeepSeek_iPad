import Foundation
import SwiftData
import UIKit

/// 离线自检。跑的是纯逻辑：提示词组装、技能导入解析、请求体构造、余额解析。
/// 由 `DS_SELFTEST=1` 触发，结果写到沙盒 Documents/selftest.txt，headless 下也能读。
@MainActor
enum SelfTest {

    struct Result {
        var group: String
        var name: String
        var passed: Bool
        var detail: String = ""
    }

    // MARK: - 用例

    static func run() -> [Result] {
        var results: [Result] = []

        func check(_ group: String, _ name: String, _ condition: Bool, _ detail: String = "") {
            results.append(Result(group: group, name: name, passed: condition, detail: condition ? "" : detail))
        }

        // ---------- 技能导入解析 ----------

        let full = SkillParser.parse(
            markdown: """
            ---
            name: 代码审阅
            description: 按层次看代码
            ---
            正文第一行
            第二行
            """,
            fallbackName: "fallback"
        )
        check("SkillParser", "完整 frontmatter 取 name", full.name == "代码审阅", "得到 \(full.name)")
        check("SkillParser", "完整 frontmatter 取 description", full.summary == "按层次看代码", "得到 \(full.summary)")
        check("SkillParser", "正文不含 frontmatter", full.instructions == "正文第一行\n第二行", "得到 \(full.instructions)")

        let plain = SkillParser.parse(markdown: "# 标题\n内容", fallbackName: "文件名")
        check("SkillParser", "无 frontmatter 用文件名", plain.name == "文件名", "得到 \(plain.name)")
        check("SkillParser", "无 frontmatter 正文取全文", plain.instructions == "# 标题\n内容", "得到 \(plain.instructions)")

        let quoted = SkillParser.parse(
            markdown: "---\nname: \"带引号\"\ndescription: '单引号'\n---\n正文",
            fallbackName: "x"
        )
        check("SkillParser", "去掉值两侧引号", quoted.name == "带引号" && quoted.summary == "单引号",
              "得到 \(quoted.name) / \(quoted.summary)")

        let broken = SkillParser.parse(markdown: "---\nname: x\n正文", fallbackName: "兜底")
        check("SkillParser", "frontmatter 未闭合不崩", broken.name == "兜底" && broken.instructions.contains("name: x"),
              "得到 \(broken.name) / \(broken.instructions)")

        let empty = SkillParser.parse(markdown: "", fallbackName: "空")
        check("SkillParser", "空文件", empty.name == "空" && empty.instructions.isEmpty, "得到 \(empty.name)")

        // ---------- 提示词组装 ----------

        let skillA = StoredSkill(name: "技能甲", summary: "", instructions: "甲指令", isEnabled: true)
        let skillB = StoredSkill(name: "技能乙", summary: "", instructions: "乙指令", isEnabled: false)
        let skillC = StoredSkill(name: "技能丙", summary: "", instructions: "丙指令", isEnabled: true)
        let blankSkill = StoredSkill(name: "空技能", summary: "", instructions: "   ", isEnabled: true)

        check("PromptComposer", "全空返回 nil",
              PromptComposer.system(defaultPrompt: "", skills: []) == nil)
        check("PromptComposer", "只有提示词",
              PromptComposer.system(defaultPrompt: "你是助手", skills: []) == "你是助手")
        check("PromptComposer", "只有技能",
              PromptComposer.system(defaultPrompt: "", skills: [skillA])?.hasPrefix("# 技能：技能甲") == true,
              "得到 \(PromptComposer.system(defaultPrompt: "", skills: [skillA]) ?? "nil")")

        let mixed = PromptComposer.system(defaultPrompt: "你是助手", skills: [skillA, skillB, skillC]) ?? ""
        check("PromptComposer", "提示词在最前", mixed.hasPrefix("你是助手"))
        check("PromptComposer", "停用技能不参与", !mixed.contains("乙指令"))
        check("PromptComposer", "启用技能按顺序", mixed.contains("甲指令") && mixed.contains("丙指令")
              && mixed.range(of: "甲指令")!.lowerBound < mixed.range(of: "丙指令")!.lowerBound)
        check("PromptComposer", "空白指令被跳过",
              PromptComposer.system(defaultPrompt: "", skills: [blankSkill]) == nil)
        check("PromptComposer", "字数与拼好的串一致",
              PromptComposer.characterCount(defaultPrompt: "你是助手", skills: [skillA, skillB, skillC]) == mixed.count,
              "count=\(PromptComposer.characterCount(defaultPrompt: "你是助手", skills: [skillA, skillB, skillC])) expected=\(mixed.count)")

        // ---------- 请求体 ----------

        let messages: [[String: Any]] = [["role": "user", "content": [["type": "text", "text": "你好"]]]]
        let withSystem = ChatClient.makeBody(
            messages: messages,
            options: .init(thinking: true, systemPrompt: "你是助手")
        )
        check("ChatClient", "system 进请求体", (withSystem["system"] as? String) == "你是助手")

        let withoutSystem = ChatClient.makeBody(messages: messages, options: .init(systemPrompt: nil))
        check("ChatClient", "无提示词不带 system", withoutSystem["system"] == nil)

        let emptySystem = ChatClient.makeBody(messages: messages, options: .init(systemPrompt: ""))
        check("ChatClient", "空提示词不带 system", emptySystem["system"] == nil)

        check("ChatClient", "thinking 开关", withSystem["thinking"] != nil)
        let noThinking = ChatClient.makeBody(messages: messages, options: .init(thinking: false))
        check("ChatClient", "关闭思考不带 thinking", noThinking["thinking"] == nil)
        check("ChatClient", "stream 恒为 true", withSystem["stream"] as? Bool == true)

        let maxEffort = ChatClient.makeBody(
            messages: messages,
            options: .init(thinking: true, thinkingEffort: "max")
        )
        check("ChatClient", "思考强度进 output_config",
              (maxEffort["output_config"] as? [String: String])?["effort"] == "max",
              "得到 \(String(describing: maxEffort["output_config"]))")

        let effortOff = ChatClient.makeBody(
            messages: messages,
            options: .init(thinking: false, thinkingEffort: "max")
        )
        check("ChatClient", "关闭思考不带 output_config", effortOff["output_config"] == nil)
        check("ChatClient", "关闭思考不带 thinking", effortOff["thinking"] == nil)

        // ---------- 余额解析 ----------

        let normal = """
        {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"14.41","granted_balance":"10.00","topped_up_balance":"4.41"}]}
        """.data(using: .utf8)!
        if let snapshot = try? BalanceClient.decode(normal) {
            check("Balance", "总额解析", snapshot.primary?.total == "14.41", "得到 \(snapshot.primary?.total ?? "nil")")
            check("Balance", "可用标记", snapshot.isAvailable)
            check("Balance", "人民币符号", snapshot.primary?.symbol == "¥", "得到 \(snapshot.primary?.symbol ?? "nil")")
            check("Balance", "数值换算", abs((snapshot.primary?.totalValue ?? 0) - 14.41) < 0.001)
        } else {
            check("Balance", "正常响应可解析", false, "decode 抛错")
        }

        let usd = """
        {"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"3.20"}]}
        """.data(using: .utf8)!
        check("Balance", "美元符号", (try? BalanceClient.decode(usd))?.primary?.symbol == "$")

        let emptyInfos = #"{"is_available":false,"balance_infos":[]}"#.data(using: .utf8)!
        check("Balance", "空余额列表", (try? BalanceClient.decode(emptyInfos))?.primary == nil)

        let missing = #"{"is_available":true,"balance_infos":[{}]}"#.data(using: .utf8)!
        check("Balance", "缺字段退化为 0", (try? BalanceClient.decode(missing))?.primary?.total == "0")

        let garbage = "not json".data(using: .utf8)!
        check("Balance", "非 JSON 抛错", (try? BalanceClient.decode(garbage)) == nil)

        // ---------- 图片 ----------

        if let demo = makeDemoImage() {
            check("图片", "长边压到 1280 以内",
                  max(demo.width, demo.height) <= ImagePipeline.maxDimension,
                  "\(demo.width)x\(demo.height)")
            check("图片", "输出 JPEG", demo.mediaType == "image/jpeg", demo.mediaType)
            check("图片", "体积在 600KB 内", demo.data.count < 600_000, "\(demo.data.count) bytes")

            let block = demo.blockJSON
            let source = block["source"] as? [String: Any]
            check("图片", "块类型是 image", block["type"] as? String == "image")
            check("图片", "source 是 base64", source?["type"] as? String == "base64")
            check("图片", "media_type 正确", source?["media_type"] as? String == "image/jpeg")
            check("图片", "base64 非空", (source?["data"] as? String)?.isEmpty == false)

            if let restored = MessageImage.decode(from: block) {
                check("图片", "解码回环一致", restored.data == demo.data)
            } else {
                check("图片", "解码回环一致", false, "decode 返回 nil")
            }

            check("图片", "空数据不崩", ImagePipeline.make(from: Data()) == nil)
        } else {
            check("图片", "测试图能生成", false)
        }

        // ---------- 内置技能 ----------

        let builtinNames = BuiltinSkills.all.map(\.name)
        check("内置技能", "有两个", BuiltinSkills.all.count == 2, "实际 \(BuiltinSkills.all.count)")
        check("内置技能", "名称非空且不重复",
              !builtinNames.contains(where: \.isEmpty) && Set(builtinNames).count == builtinNames.count,
              "\(builtinNames)")
        check("内置技能", "指令都有实质内容",
              BuiltinSkills.all.allSatisfy { $0.instructions.count > 20 },
              BuiltinSkills.all.map { "\($0.name):\($0.instructions.count)" }.joined(separator: ", "))

        let builtinSkill = StoredSkill(
            name: BuiltinSkills.all[0].name,
            instructions: BuiltinSkills.all[0].instructions
        )
        let customSkill = StoredSkill(name: "我自己写的", instructions: "x")
        check("内置技能", "能认出内置条目", SkillInstaller.isBuiltin(builtinSkill))
        check("内置技能", "用户自建不算内置", !SkillInstaller.isBuiltin(customSkill))

        // ---------- 落盘 ----------

        runPersistenceCheck(&results)

        return results
    }

    /// 用临时目录单独开一个库，验证「写入 → 关掉 → 重新打开还能读到」。
    /// 不碰用户真实的会话库。
    private static func runPersistenceCheck(_ results: inout [Result]) {
        let schema = Schema([StoredConversation.self, StoredMessage.self, StoredSkill.self])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-store-\(UUID().uuidString)")
        let storeURL = directory.appendingPathComponent("test.store")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let config = ModelConfiguration(schema: schema, url: storeURL)

            let first = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(first)
            context.insert(StoredSkill(name: "持久化验证", summary: "", instructions: "指令正文"))
            context.insert(StoredConversation(title: "验证会话", model: "deepseek-flash"))
            try context.save()

            let second = try ModelContainer(for: schema, configurations: config)
            let reopen = ModelContext(second)
            let skills = try reopen.fetch(FetchDescriptor<StoredSkill>())
            let conversations = try reopen.fetch(FetchDescriptor<StoredConversation>())

            results.append(Result(group: "持久化", name: "技能写入后重开还在",
                                  passed: skills.count == 1 && skills.first?.name == "持久化验证",
                                  detail: "skills=\(skills.count)"))
            results.append(Result(group: "持久化", name: "会话写入后重开还在",
                                  passed: conversations.count == 1 && conversations.first?.title == "验证会话",
                                  detail: "conversations=\(conversations.count)"))

            try? FileManager.default.removeItem(at: directory)
        } catch {
            results.append(Result(group: "持久化", name: "临时库可打开",
                                  passed: false, detail: "\(error)"))
        }
    }

    /// 生成一张带文字的测试图，同时给自检和截图钩子用。
    static func makeDemoImage(text: String = "DEEPSEEK TEST 42", hue: CGFloat = 0.6) -> MessageImage? {
        let size = CGSize(width: 960, height: 640)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor(hue: hue, saturation: 0.62, brightness: 0.95, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 140))

            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            text.draw(at: CGPoint(x: 48, y: 38), withAttributes: title)

            let body: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 42, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            let lines = ["resolution 960 x 640", "purpose: pipeline check"]
            for (index, line) in lines.enumerated() {
                line.draw(at: CGPoint(x: 48, y: 240 + CGFloat(index) * 70), withAttributes: body)
            }
        }

        guard let png = image.pngData() else { return nil }
        return ImagePipeline.make(from: png)
    }

    // MARK: - 写报告

    @discardableResult
    static func writeReport() -> String {
        let results = run()
        let failures = results.filter { !$0.passed }

        var lines: [String] = results.map { result in
            result.passed
                ? "[PASS] \(result.group) · \(result.name)"
                : "[FAIL] \(result.group) · \(result.name) | \(result.detail)"
        }
        lines.append("")
        lines.append("\(results.count - failures.count) passed / \(failures.count) failed / \(results.count) total")

        let text = lines.joined(separator: "\n") + "\n"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("selftest.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return text
    }
}
