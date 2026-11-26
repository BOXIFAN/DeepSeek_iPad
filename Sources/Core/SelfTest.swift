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

        // ---------- 长期记忆 ----------

        let memUser = StoredMemory(content: "用户是昆士兰大学计算机科学学生",
                                   target: .user,
                                   importance: .critical)
        let memWork = StoredMemory(content: "iPad-DS 不做后端", target: .memory)
        let memOff = StoredMemory(content: "这条已经停用", target: .user, isEnabled: false)

        let section = MemoryComposer.section([memUser, memWork, memOff]) ?? ""
        check("Memory", "两栏都有标签",
              section.contains("<memory target=\"user\">") && section.contains("<memory target=\"memory\">"),
              "得到 \(section.prefix(60))")
        check("Memory", "停用条目不注入", !section.contains("这条已经停用"))
        check("Memory", "重要条目带标记", section.contains("[重要] 用户是昆士兰大学"))
        check("Memory", "空记忆不产生段落", MemoryComposer.section([]) == nil)
        check("Memory", "只有停用也返回 nil", MemoryComposer.section([memOff]) == nil)

        let withMemory = PromptComposer.system(defaultPrompt: "你是助手",
                                               skills: [skillA],
                                               memories: [memUser]) ?? ""
        check("Memory", "记忆排在技能之后",
              withMemory.range(of: "甲指令")!.lowerBound < withMemory.range(of: "长期记忆")!.lowerBound)
        check("Memory", "记忆段落参与 system 字数",
              PromptComposer.characterCount(defaultPrompt: "你是助手",
                                            skills: [skillA],
                                            memories: [memUser]) == withMemory.count)

        // 预算：100 条 × 101 字，肯定超过 6000
        var many: [StoredMemory] = []
        for index in 0..<100 {
            many.append(StoredMemory(content: String(repeating: "字", count: 100) + "\(index)"))
        }
        let selection = MemoryComposer.select(many)
        let selectedCharacters = selection.included.reduce(0) { $0 + $1.characterCount }
        check("Memory", "预算内不超过 6000 字",
              selectedCharacters <= MemoryBudget.maxCharacters,
              "用掉 \(selectedCharacters)")
        check("Memory", "超出预算的条目被记下来", !selection.omitted.isEmpty,
              "omitted=\(selection.omitted.count)")
        check("Memory", "条目数上限是 80",
              MemoryBudget.usage(of: many).count == 100 && MemoryBudget.maxCount == 80)

        // 去重
        check("Memory", "相近句相似度高",
              MemorySimilarity.score("用户喜欢先看数字", "用户喜欢先看数字和事实") >= 0.7)
        check("Memory", "无关句不判重",
              MemorySimilarity.duplicate(of: "今天武汉下雨", in: [memUser, memWork]) == nil)
        check("Memory", "完全重复命中已有条目",
              MemorySimilarity.duplicate(of: memUser.content, in: [memUser, memWork])?.id == memUser.id)

        // 显式命令
        check("Memory", "记住：解析出内容", MemoryCommand.payload("记住：我不吃香菜") == "我不吃香菜")
        check("Memory", "半角冒号也认", MemoryCommand.payload("记住:用 Swift 写") == "用 Swift 写")
        check("Memory", "没有冒号不触发", MemoryCommand.payload("记住这个方案") == nil)
        check("Memory", "空内容不触发", MemoryCommand.payload("记住：") == nil)
        check("Memory", "前后空白被去掉", MemoryCommand.payload("  记下： 一句话  ") == "一句话")

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

        // ---------- 客户端工具 ----------

        let toolBody = ChatClient.makeBody(messages: messages, options: .init(memoryTools: true))
        let tools = toolBody["tools"] as? [[String: Any]]
        check("Tool", "带上 remember 工具", tools?.count == 1, "得到 \(tools?.count ?? -1)")
        check("Tool", "客户端工具不带 type", tools?.first?["type"] == nil)
        check("Tool", "工具名是 remember", tools?.first?["name"] as? String == "remember")
        check("Tool", "input_schema 顶层是 object",
              (tools?.first?["input_schema"] as? [String: Any])?["type"] as? String == "object")
        check("Tool", "内容参数必填",
              ((tools?.first?["input_schema"] as? [String: Any])?["required"] as? [String]) == ["content"])

        let noTools = ChatClient.makeBody(messages: messages, options: .init())
        check("Tool", "不开工具时不带 tools", noTools["tools"] == nil)

        let mixedTools = ChatClient.makeBody(messages: messages,
                                             options: .init(webSearch: true, memoryTools: true))
        check("Tool", "联网与记忆共存",
              (mixedTools["tools"] as? [[String: Any]])?.count == 3)

        let toolRaw: [String: Any] = [
            "type": "tool_use",
            "id": "toolu_1",
            "name": "remember",
            "input": ["content": "用户喜欢先看数字", "target": "user"]
        ]
        if case .toolUse(let toolID, let toolName, let inputJSON)? = ContentBlock.make(from: toolRaw, id: "fallback") {
            check("Tool", "tool_use 解出服务端 id", toolID == "toolu_1")
            check("Tool", "tool_use 解出工具名", toolName == "remember")
            check("Tool", "tool_use 保留原始参数",
                  ContentBlock.memoryText(from: inputJSON) == "用户喜欢先看数字",
                  "得到 \(inputJSON)")
        } else {
            check("Tool", "tool_use 能解码", false)
        }

        check("Tool", "从参数里取要展示的一句话",
              ContentBlock.memoryText(from: #"{"content":"一句话"}"#) == "一句话")
        check("Tool", "空 content 不展示",
              ContentBlock.memoryText(from: #"{"content":"   "}"#) == nil)

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

        // ---------- 用量解析 ----------

        let anthropicUsage = Usage.from([
            "input_tokens": 1_000,
            "cache_read_input_tokens": 9_000,
            "cache_creation_input_tokens": 0,
            "output_tokens": 500
        ])
        check("Usage", "Anthropic 口径总输入 = 未命中 + 命中",
              anthropicUsage?.totalInputTokens == 10_000,
              "得到 \(anthropicUsage?.totalInputTokens ?? -1)")
        check("Usage", "命中率按总输入算",
              abs((anthropicUsage?.cacheHitRate ?? 0) - 0.9) < 0.0001,
              "得到 \(anthropicUsage?.cacheHitRate ?? -1)")
        check("Usage", "输出计入总量", anthropicUsage?.totalTokens == 10_500)

        let nativeUsage = Usage.from([
            "prompt_tokens": 10_000,
            "prompt_cache_hit_tokens": 9_000,
            "completion_tokens": 500
        ])
        check("Usage", "原生口径不把命中量加两遍",
              nativeUsage?.totalInputTokens == 10_000,
              "得到 \(nativeUsage?.totalInputTokens ?? -1)")
        check("Usage", "原生口径命中率",
              abs((nativeUsage?.cacheHitRate ?? 0) - 0.9) < 0.0001,
              "得到 \(nativeUsage?.cacheHitRate ?? -1)")

        let startUsage = Usage.from([
            "input_tokens": 1_000,
            "cache_read_input_tokens": 9_000,
            "output_tokens": 1
        ])
        let deltaUsage = Usage.from(["output_tokens": 500])
        let merged = startUsage?.merged(with: deltaUsage ?? Usage())
        check("Usage", "两段 usage 合并保留输入与缓存",
              merged?.totalInputTokens == 10_000,
              "得到 \(merged?.totalInputTokens ?? -1)")
        check("Usage", "合并取最终输出", merged?.outputTokens == 500,
              "得到 \(merged?.outputTokens ?? -1)")

        check("Usage", "没有缓存时命中率为 0",
              Usage.from(["input_tokens": 800])?.cacheHitRate == 0)
        check("Usage", "空字典不崩", Usage.from([:])?.totalTokens == 0)

        // ---------- 会话指标 ----------

        check("Metrics", "小于一千直接显示", SessionMetrics.tokenText(812) == "812")
        check("Metrics", "千级一位小数", SessionMetrics.tokenText(3_240) == "3.2K")
        check("Metrics", "大数字取整", SessionMetrics.tokenText(972_000) == "972K")
        check("Metrics", "百万级", SessionMetrics.tokenText(1_000_000) == "1.0M")
        check("Metrics", "缓存百分比", SessionMetrics.cacheText(0.9) == "90%")
        check("Metrics", "速度取整", SessionMetrics.rateText(46.4) == "46 tok/s")
        check("Metrics", "低速保留一位", SessionMetrics.rateText(7.25) == "7.2 tok/s")
        check("Metrics", "非法速度返回 nil", SessionMetrics.rateText(0) == nil)
        check("Metrics", "字符估 token", SessionMetrics.estimatedTokens(forCharacters: 2_600) == 1_000)

        var metrics = SessionMetrics()
        metrics.reset(for: ModelCatalog.flash)
        metrics.apply(Usage(inputTokens: 1_000,
                            outputTokens: 500,
                            cacheReadTokens: 28_500),
                      model: nil,
                      tokensPerSecond: 40)
        check("Metrics", "剩余 = 窗口 - 已用",
              metrics.remainingTokens == 970_000,
              "得到 \(metrics.remainingTokens)")
        check("Metrics", "未用满不告警", !metrics.isNearLimit)
        check("Metrics", "窗口取模型表", metrics.contextWindow == 1_000_000)

        var nearLimit = SessionMetrics()
        nearLimit.reset(for: ModelCatalog.flash)
        nearLimit.usedTokens = 900_000
        check("Metrics", "剩余不到 15% 告警", nearLimit.isNearLimit)
        check("Metrics", "剩余不为负",
              SessionMetrics(usedTokens: 1_200_000).remainingTokens == 0)

        // ---------- 余额重试策略 ----------

        check("Retry", "第 1 次等 5 秒", BalanceRetryPolicy.delay(afterFailure: 1) == 5)
        check("Retry", "第 4 次等 120 秒", BalanceRetryPolicy.delay(afterFailure: 4) == 120)
        check("Retry", "第 5 次不再重试", BalanceRetryPolicy.delay(afterFailure: 5) == nil)
        check("Retry", "401 不重试", !BalanceRetryPolicy.isRetryable(BalanceError.http(401)))
        check("Retry", "402 不重试", !BalanceRetryPolicy.isRetryable(BalanceError.http(402)))
        check("Retry", "429 重试", BalanceRetryPolicy.isRetryable(BalanceError.http(429)))
        check("Retry", "503 重试", BalanceRetryPolicy.isRetryable(BalanceError.http(503)))
        check("Retry", "断网重试", BalanceRetryPolicy.isRetryable(BalanceError.offline))
        check("Retry", "超时重试", BalanceRetryPolicy.isRetryable(BalanceError.timeout))
        check("Retry", "主动取消不重试", !BalanceRetryPolicy.isRetryable(BalanceError.cancelled))

        // ---------- 文档 ----------

        let pdfURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let mdURL = URL(fileURLWithPath: "/tmp/notes.md")
        let swiftURL = URL(fileURLWithPath: "/tmp/main.swift")
        let xlsxURL = URL(fileURLWithPath: "/tmp/budget.xlsx")
        let pngURL = URL(fileURLWithPath: "/tmp/photo.png")
        let zipURL = URL(fileURLWithPath: "/tmp/archive.zip")

        check("文档", "PDF 走解析", DocumentKind.kind(for: pdfURL) == .parsed)
        check("文档", "Markdown 走 user_data", DocumentKind.kind(for: mdURL) == .data)
        check("文档", "代码文件走 user_data", DocumentKind.kind(for: swiftURL) == .data)
        check("文档", "XLSX 走 user_data", DocumentKind.kind(for: xlsxURL) == .data)
        check("文档", "图片不算文档", DocumentKind.kind(for: pngURL) == nil)
        check("文档", "压缩包不支持", DocumentKind.kind(for: zipURL) == nil)

        check("文档", "默认只解析文字",
              DocumentKind.purpose(for: .parsed, keepLayout: false) == .textRecognition)
        check("文档", "开关后图文混排",
              DocumentKind.purpose(for: .parsed, keepLayout: true) == .richLayoutRecognition)
        check("文档", "文本不受开关影响",
              DocumentKind.purpose(for: .data, keepLayout: true) == .userData)
        check("文档", "PDF 上限 100MiB",
              DocumentKind.maxBytes(for: .parsed) == 100 * 1024 * 1024)
        check("文档", "文本上限 32MiB",
              DocumentKind.maxBytes(for: .data) == 32 * 1024 * 1024)

        let boundary = "----test"
        let multipart = FileUploader.multipartBody(
            boundary: boundary,
            filename: "报告.pdf",
            purpose: .richLayoutRecognition,
            data: Data("hello-doc".utf8)
        )
        let multipartText = String(decoding: multipart, as: UTF8.self)
        let purposeIndex = multipartText.range(of: "name=\"purpose\"")
        let fileIndex = multipartText.range(of: "name=\"file\"")
        check("文档", "multipart 里 purpose 在 file 之前",
              purposeIndex != nil && fileIndex != nil
              && purposeIndex!.lowerBound < fileIndex!.lowerBound,
              multipartText)
        check("文档", "multipart 带文件名", multipartText.contains("filename=\"报告.pdf\""))
        check("文档", "multipart 带正文", multipartText.contains("hello-doc"))
        check("文档", "multipart 以 boundary 收尾", multipartText.hasSuffix("--\(boundary)--\r\n"))
        check("文档", "purpose 值正确", multipartText.contains("rich_layout_recognition"))
        check("文档", "文件名去掉引号与换行",
              !FileUploader.safeFilename("a\"b\nc.pdf").contains("\""))

        let document = MessageDocument(fileID: "file-api-1",
                                       filename: "a.pdf",
                                       byteCount: 1024,
                                       purpose: .textRecognition)
        let documentBlock = document.blockJSON
        let documentSource = documentBlock["source"] as? [String: Any]
        check("文档", "块类型是 document", documentBlock["type"] as? String == "document")
        check("文档", "source 是 file", documentSource?["type"] as? String == "file")
        check("文档", "file_id 正确", documentSource?["file_id"] as? String == "file-api-1")
        check("文档", "尺寸文案非空", !document.sizeText.isEmpty)

        let uploadJSON = #"{"id":"file-api-9","filename":"报表.pdf","bytes":2048,"purpose":"text_recognition"}"#
        if let decoded = try? FileUploader.decode(Data(uploadJSON.utf8),
                                                  fallbackFilename: "fallback.pdf",
                                                  requestedPurpose: .userData) {
            check("文档", "上传响应解析 id", decoded.fileID == "file-api-9")
            check("文档", "上传响应解析文件名", decoded.filename == "报表.pdf")
            check("文档", "上传响应解析大小", decoded.byteCount == 2048)
            check("文档", "上传响应解析 purpose", decoded.purpose == .textRecognition)
        } else {
            check("文档", "上传响应可解析", false, "decode 抛错")
        }
        check("文档", "坏响应抛错",
              (try? FileUploader.decode(Data("nope".utf8),
                                        fallbackFilename: "x",
                                        requestedPurpose: .userData)) == nil)

        check("ChatClient", "含 document 块带 files beta",
              ChatClient.needsFilesBeta(messages: [["role": "user", "content": [documentBlock]]]))
        check("ChatClient", "纯文本消息不带 beta",
              !ChatClient.needsFilesBeta(messages: [["role": "user",
                                                    "content": [["type": "text", "text": "hi"]]]]))
        check("ChatClient", "图片消息不带 beta",
              !ChatClient.needsFilesBeta(messages: [["role": "user",
                                                    "content": [["type": "image",
                                                                 "source": ["type": "base64"]]]]]))

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

        // ---------- 开屏 ----------

        check("开屏", "鲸鱼素材可加载", UIImage(named: "SplashWhale") != nil)

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
        let schema = Schema([StoredConversation.self,
                             StoredMessage.self,
                             StoredSkill.self,
                             StoredMemory.self])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-store-\(UUID().uuidString)")
        let storeURL = directory.appendingPathComponent("test.store")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let config = ModelConfiguration(schema: schema, url: storeURL)

            let first = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(first)
            context.insert(StoredSkill(name: "持久化验证", summary: "", instructions: "指令正文"))
            context.insert(StoredMemory(content: "记忆写入后重开还在", target: .memory))

            let conversation = StoredConversation(title: "验证会话", model: "deepseek-flash")
            context.insert(conversation)

            let blocks: [[String: Any]] = [["type": "text", "text": "回答"]]
            let blocksData = (try? JSONSerialization.data(withJSONObject: blocks)) ?? Data()
            let message = StoredMessage(order: 0,
                                        role: "assistant",
                                        blocksJSON: blocksData,
                                        plainText: "回答",
                                        usage: Usage(inputTokens: 1_000,
                                                     outputTokens: 500,
                                                     cacheReadTokens: 9_000),
                                        documents: [MessageDocument(fileID: "file-api-1",
                                                                    filename: "a.pdf",
                                                                    byteCount: 1024,
                                                                    purpose: .textRecognition)])
            message.conversation = conversation
            context.insert(message)
            try context.save()

            let second = try ModelContainer(for: schema, configurations: config)
            let reopen = ModelContext(second)
            let skills = try reopen.fetch(FetchDescriptor<StoredSkill>())
            let conversations = try reopen.fetch(FetchDescriptor<StoredConversation>())
            let messages = try reopen.fetch(FetchDescriptor<StoredMessage>())
            let memories = try reopen.fetch(FetchDescriptor<StoredMemory>())

            results.append(Result(group: "持久化", name: "技能写入后重开还在",
                                  passed: skills.count == 1 && skills.first?.name == "持久化验证",
                                  detail: "skills=\(skills.count)"))
            results.append(Result(group: "持久化", name: "会话写入后重开还在",
                                  passed: conversations.count == 1 && conversations.first?.title == "验证会话",
                                  detail: "conversations=\(conversations.count)"))
            results.append(Result(group: "持久化", name: "记忆写入后重开还在",
                                  passed: memories.count == 1
                                        && memories.first?.content == "记忆写入后重开还在"
                                        && memories.first?.target == .memory,
                                  detail: "memories=\(memories.count)"))
            results.append(Result(group: "持久化", name: "用量随消息落库",
                                  passed: messages.first?.usage?.totalInputTokens == 10_000,
                                  detail: "usage=\(String(describing: messages.first?.usage))"))
            results.append(Result(group: "持久化", name: "附件元数据落库",
                                  passed: messages.first?.documents.first?.fileID == "file-api-1",
                                  detail: "documents=\(String(describing: messages.first?.documents))"))

            try? FileManager.default.removeItem(at: directory)
        } catch {
            results.append(Result(group: "持久化", name: "临时库可打开",
                                  passed: false, detail: "\(error)"))
        }
    }

    /// 生成一份最小 PDF，给端到端上传验证用（模拟器沙盒里 App 自己写，绕开宿主 cp 限制）。
    static func makeDemoPDF() -> (filename: String, data: Data)? {
        let pdf = """
        %PDF-1.4
        1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
        2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
        3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 200]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
        4 0 obj<</Length 60>>stream
        BT /F1 12 Tf 20 120 Td (iPadDS File Reading Test) Tj ET
        endstream
        endobj
        5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
        trailer<</Root 1 0 R>>
        %%EOF
        """
        return ("ds-test-doc.pdf", Data(pdf.utf8))
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
