import SwiftUI
import SwiftData

/// 设置页。自用场景只放必要项：Key、模型、默认开关、提示词与技能。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage("model") private var model = "deepseek-flash"
    @AppStorage(ThinkingEffort.storageKey) private var effortRaw = ThinkingEffort.standard.rawValue
    @AppStorage("defaultSearch") private var defaultSearch = false
    @AppStorage("systemPrompt") private var systemPrompt = ""
    @AppStorage("memoryTools") private var memoryTools = true

    @Query(sort: \StoredSkill.createdAt, order: .forward)
    private var skills: [StoredSkill]

    @Query(sort: \StoredMemory.createdAt, order: .forward)
    private var memories: [StoredMemory]

    @State private var keyDraft = ""
    @State private var hasSavedKey = KeychainStore.hasAPIKey
    @State private var justSaved = false

    @State private var path: [SettingsPage] = {
        switch ProcessInfo.processInfo.environment["DS_SETTINGS_PAGE"] {
        case "prompt": return [.prompt]
        case "skills": return [.skills]
        case "memory": return [.memories]
        default: return []
        }
    }()

    enum SettingsPage: Hashable {
        case prompt
        case skills
        case memories
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                keySection
                modelSection
                toggleSection
                memoryToggleSection
                promptSection

                if hasSavedKey {
                    Section {
                        Button("删除已保存的 Key", role: .destructive) {
                            KeychainStore.delete()
                            hasSavedKey = false
                            justSaved = false
                            keyDraft = ""
                            BalanceStore.shared.reset()
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .prompt: SystemPromptView()
                case .skills: SkillsView()
                case .memories: MemoriesView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 分区

    private var keySection: some View {
        Section {
            if hasSavedKey && !justSaved {
                HStack {
                    Label("已保存 API Key", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Button("更换") {
                        hasSavedKey = false
                        keyDraft = ""
                    }
                    .font(.footnote)
                }
            } else {
                SecureField("sk-...", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                Button("保存到 Keychain") {
                    let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if KeychainStore.save(trimmed) {
                        hasSavedKey = true
                        justSaved = true
                        keyDraft = ""
                        BalanceStore.shared.refresh()
                    }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("API Key")
        } footer: {
            Text("Key 只保存在本机 Keychain，不会离开这台设备。到 platform.deepseek.com 创建。")
        }
    }

    private var modelSection: some View {
        Section("模型") {
            Picker("默认模型", selection: $model) {
                Text("deepseek-flash").tag("deepseek-flash")
                Text("deepseek-v4-pro").tag("deepseek-v4-pro")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var toggleSection: some View {
        Group {
            Section {
                Picker("思考强度", selection: $effortRaw) {
                    ForEach(ThinkingEffort.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("思考")
            } footer: {
                Text("对应请求里的 output_config.effort：低 = low，标准 = high，高 = max。关闭后不发送 thinking，也不输出思维链。")
            }

            Section {
                Toggle("默认开启联网搜索", isOn: $defaultSearch)
            } footer: {
                Text("开启联网后，温度这类参数会被服务端忽略。")
            }
        }
    }

    private var memoryToggleSection: some View {
        Section {
            Toggle("让模型自己记", isOn: $memoryTools)
        } header: {
            Text("记忆")
        } footer: {
            Text("开启后，模型遇到值得跨对话保留的偏好、身份或项目事实，会调用 remember 工具写入。重复的不会写；遇到停止、失败或输出截断时不会续轮。")
        }
    }

    private var promptSection: some View {
        Section {
            NavigationLink(value: SettingsPage.prompt) {
                LabeledContent("系统提示词", value: promptSummary)
            }
            NavigationLink(value: SettingsPage.skills) {
                LabeledContent("技能", value: skillSummary)
            }
            NavigationLink(value: SettingsPage.memories) {
                LabeledContent("记忆", value: memorySummary)
            }
        } header: {
            Text("提示词")
        } footer: {
            Text("默认提示词、启用的技能与记忆会拼成 system，随每次请求发给模型。\(combinedSummary)")
        }
    }

    // MARK: - 摘要

    private var promptSummary: String {
        let count = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count == 0 ? "未设置" : "\(count) 字"
    }

    /// 拼起来之后实际会发出去的字数，含技能标题、记忆标签与分隔线。
    private var combinedSummary: String {
        let combined = PromptComposer.system(defaultPrompt: systemPrompt,
                                             skills: skills,
                                             memories: memories)
        let enabled = skills.filter(\.isEnabled).count
        let enabledMemories = memories.filter(\.isEnabled).count
        guard let combined else { return " 现在没有内容会发送。" }
        return " 当前共 \(combined.count) 字（默认提示词 + \(enabled) 个技能 + \(enabledMemories) 条记忆）。"
    }

    private var memorySummary: String {
        let usage = MemoryBudget.usage(of: memories)
        guard usage.count > 0 else { return "未设置" }
        return "\(usage.count) 条 · \(usage.characters) 字"
    }

    private var skillSummary: String {
        if skills.isEmpty { return "没有技能" }
        let enabled = skills.filter(\.isEnabled).count
        return enabled == 0 ? "\(skills.count) 个，全停用" : "已启用 \(enabled) 个"
    }
}
