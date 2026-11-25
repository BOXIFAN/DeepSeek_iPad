import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 技能列表

struct SkillsView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \StoredSkill.createdAt, order: .forward)
    private var skills: [StoredSkill]

    @State private var importing = false
    @State private var importError: String?

    private var enabledCount: Int {
        skills.filter(\.isEnabled).count
    }

    var body: some View {
        List {
            if skills.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(skills) { skill in
                        NavigationLink {
                            SkillEditorView(skill: skill)
                        } label: {
                            row(skill)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggle(skill)
                            } label: {
                                Label(skill.isEnabled ? "停用" : "启用",
                                      systemImage: skill.isEnabled ? "pause.circle" : "play.circle")
                            }
                            .tint(Theme.accent)
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("启用的技能按顺序拼在系统提示词后面，随每次请求发送。技能只提供指令，不执行脚本。")
                }
            }
        }
        .navigationTitle("技能")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        createSkill()
                    } label: {
                        Label("新建技能", systemImage: "square.and.pencil")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("从 Markdown 导入", systemImage: "doc.badge.plus")
                    }
                    Button {
                        SkillInstaller.installMissing(force: true)
                    } label: {
                        Label("恢复内置技能", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: markdownTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var markdownTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        return types
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("还没有技能")
                    .font(.system(size: 15, weight: .medium))
                Text("技能是一段可复用的指令。可以把常用的角色设定、输出格式、检查清单存成技能，需要时打开。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    importing = true
                } label: {
                    Label("从 Markdown 导入", systemImage: "doc.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 6)
        }
    }

    private func row(_ skill: StoredSkill) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                if SkillInstaller.isBuiltin(skill) {
                    Text("内置")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.07))
                        )
                }
                if skill.isEnabled {
                    Text("启用")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(Theme.accent.opacity(0.12))
                        )
                }
                Spacer(minLength: 0)
            }

            if !skill.summary.isEmpty {
                Text(skill.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("\(skill.characterCount) 字")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    // MARK: - 动作

    private func createSkill() {
        let skill = StoredSkill(name: "未命名技能")
        context.insert(skill)
        try? context.save()
    }

    private func toggle(_ skill: StoredSkill) {
        skill.isEnabled.toggle()
        skill.updatedAt = Date()
        try? context.save()
    }

    private func delete(_ indexSet: IndexSet) {
        for index in indexSet {
            context.delete(skills[index])
        }
        try? context.save()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var failure: String?
            for url in urls {
                let accessible = url.startAccessingSecurityScopedResource()
                defer { if accessible { url.stopAccessingSecurityScopedResource() } }
                do {
                    let raw = try Data(contentsOf: url)
                    guard let text = String(data: raw, encoding: .utf8)
                            ?? String(data: raw, encoding: .isoLatin1) else {
                        failure = "\(url.lastPathComponent) 不是纯文本，读不了"
                        continue
                    }
                    let fallback = url.deletingPathExtension().lastPathComponent
                    let draft = SkillParser.parse(markdown: text, fallbackName: fallback)
                    let skill = StoredSkill(
                        name: draft.name,
                        summary: draft.summary,
                        instructions: draft.instructions,
                        isEnabled: true,
                        imported: true
                    )
                    context.insert(skill)
                } catch {
                    failure = "读不了 \(url.lastPathComponent)：\(error.localizedDescription)"
                }
            }
            try? context.save()
            importError = failure
        }
    }
}

// MARK: - 技能编辑

struct SkillEditorView: View {
    @Bindable var skill: StoredSkill
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("技能名", text: $skill.name)
                    .font(.system(size: 15, weight: .medium))
            } footer: {
                Text("会作为小标题拼进 system，模型看到的是「# 技能：名称」。")
            }

            Section("一句话说明") {
                TextField("这段指令是干什么的", text: $skill.summary, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                TextEditor(text: $skill.instructions)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .frame(minHeight: 240)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("指令")
            } footer: {
                Text("写清角色、步骤、输出格式和边界。技能里不能引用 App 读不到的文件。")
            }

            Section {
                Toggle("启用", isOn: $skill.isEnabled)
            } footer: {
                Text("启用后，每次发送都会带上这段指令。\(skill.characterCount) 字。")
            }

            Section {
                Button("删除这个技能", role: .destructive) {
                    context.delete(skill)
                    try? context.save()
                    dismiss()
                }
            }
        }
        .navigationTitle(skill.name.isEmpty ? "技能" : skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: skill.name) { _, _ in touch() }
        .onChange(of: skill.summary) { _, _ in touch() }
        .onChange(of: skill.instructions) { _, _ in touch() }
        .onDisappear {
            try? context.save()
        }
    }

    private func touch() {
        skill.updatedAt = Date()
    }
}
