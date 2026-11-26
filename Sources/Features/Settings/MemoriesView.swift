import SwiftUI
import SwiftData

// MARK: - 记忆列表

/// 设置里的记忆页：两栏条目、容量条、编辑与删除。
struct MemoriesView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \StoredMemory.createdAt, order: .forward)
    private var memories: [StoredMemory]

    @State private var showNew = false

    private var usage: (count: Int, characters: Int) {
        MemoryBudget.usage(of: memories)
    }

    var body: some View {
        List {
            Section {
                MemoryCapacityBar(count: usage.count, characters: usage.characters)
            } footer: {
                Text("启用的记忆会拼在系统提示词与技能之后，随每次请求发送。上限 \(MemoryBudget.maxCount) 条 / \(MemoryBudget.maxCharacters) 字，超出预算的条目不会被注入。")
            }

            if memories.isEmpty {
                emptySection
            } else {
                ForEach(MemoryTarget.allCases) { target in
                    let group = memories.filter { $0.target == target }
                    if !group.isEmpty {
                        Section {
                            ForEach(group) { memory in
                                NavigationLink {
                                    MemoryEditorView(memory: memory)
                                } label: {
                                    row(memory)
                                }
                            }
                            .onDelete { offsets in
                                delete(offsets, in: group)
                            }
                        } header: {
                            HStack {
                                Text(target.title)
                                Spacer()
                                Text("\(group.count) 条")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建记忆")
            }
        }
        .sheet(isPresented: $showNew) {
            MemoryQuickAddSheet(initialContent: "", initialTarget: .user)
        }
    }

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("还没有记忆")
                    .font(.system(size: 15, weight: .medium))
                Text("记忆是一条长期有效的事实，比如你的习惯、常用项目的配置、已经定下的约定。存下来之后，每次对话都会带上它。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("也可以在输入框里打「记住：……」直接存一条。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
    }

    private func row(_ memory: StoredMemory) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(memory.trimmedContent)
                .font(.system(size: 14))
                .lineLimit(3)
                .foregroundStyle(memory.isEnabled ? Color.primary : Color.secondary)

            HStack(spacing: 6) {
                if memory.importance == .critical {
                    badge("重要", color: Theme.accent)
                }
                badge(sourceTitle(memory.source), color: .secondary)
                if !memory.isEnabled {
                    badge("已停用", color: .secondary)
                }
                Spacer(minLength: 0)
                Text(memory.createdAt, format: .dateTime.month().day())
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func sourceTitle(_ source: String) -> String {
        switch source {
        case "tool": return "自动"
        case "message": return "来自消息"
        default: return "手动"
        }
    }

    private func delete(_ offsets: IndexSet, in group: [StoredMemory]) {
        for index in offsets {
            MemoryStore.shared.delete(group[index])
        }
    }
}

// MARK: - 容量条

struct MemoryCapacityBar: View {

    var count: Int
    var characters: Int

    private var countRatio: Double {
        Double(count) / Double(MemoryBudget.maxCount)
    }

    private var characterRatio: Double {
        Double(characters) / Double(MemoryBudget.maxCharacters)
    }

    private var tint: Color {
        max(countRatio, characterRatio) >= 0.85 ? .orange : Theme.accent
    }

    private var ratio: Double {
        min(max(countRatio, characterRatio), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 12, weight: .medium))
                Text("已用 \(count)/\(MemoryBudget.maxCount) 条 · \(characters)/\(MemoryBudget.maxCharacters) 字")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)

            // 自己画一条，系统 ProgressView 在 List row 里会把宽度撑出卡片
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule().fill(tint)
                        .frame(width: max(3, proxy.size.width * ratio))
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 编辑

struct MemoryEditorView: View {

    @Bindable var memory: StoredMemory
    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""
    @State private var target: MemoryTarget = .user
    @State private var importance: MemoryImportance = .normal
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("一句话事实", text: $content, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.system(size: 15))
            } header: {
                Text("内容")
            } footer: {
                Text("\(content.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(MemoryBudget.maxEntryLength) 字。写成陈述句，一条只讲一件事。")
            }

            Section {
                Picker("分栏", selection: $target) {
                    ForEach(MemoryTarget.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Picker("重要性", selection: $importance) {
                    ForEach(MemoryImportance.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("「关于你」放身份与偏好，「工作参考」放项目与环境。重要的条目会带标记，预算吃紧时最后被裁掉。")
            }

            Section {
                Toggle("启用", isOn: Binding(
                    get: { memory.isEnabled },
                    set: { MemoryStore.shared.setEnabled(memory, $0) }
                ))
            } footer: {
                Text("停用后不再注入请求，条目保留。")
            }

            Section {
                Button("删除这条记忆", role: .destructive) {
                    MemoryStore.shared.delete(memory)
                    dismiss()
                }
            }
        }
        .navigationTitle("编辑记忆")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("没保存", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .onAppear {
            guard !loaded else { return }
            content = memory.content
            target = memory.target
            importance = memory.importance
            loaded = true
        }
    }

    private func save() {
        switch MemoryStore.shared.update(memory,
                                         content: content,
                                         target: target,
                                         importance: importance) {
        case .saved:
            dismiss()
        case .duplicate(let other):
            errorText = "和已有记忆太像：\(other.trimmedContent)"
        case .tooLong(let limit):
            errorText = "一条最多 \(limit) 字，拆成几条更稳"
        case .empty:
            errorText = "内容不能为空"
        case .full(let message):
            errorText = message
        }
    }
}

// MARK: - 新建

struct MemoryQuickAddSheet: View {

    var initialContent: String = ""
    var initialTarget: MemoryTarget = .user

    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""
    @State private var target: MemoryTarget = .user
    @State private var importance: MemoryImportance = .normal
    @State private var errorText: String?
    @State private var loaded = false

    private var trimmed: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("一句话事实", text: $content, axis: .vertical)
                        .lineLimit(4...10)
                        .font(.system(size: 15))
                } header: {
                    Text("内容")
                } footer: {
                    Text("\(trimmed.count)/\(MemoryBudget.maxEntryLength) 字。写成陈述句，一条只讲一件事。下发后每次对话都会带上它。")
                }

                Section {
                    Picker("分栏", selection: $target) {
                        ForEach(MemoryTarget.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("重要性", selection: $importance) {
                        ForEach(MemoryImportance.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            .navigationTitle("记住一条")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            content = initialContent
            target = initialTarget
            loaded = true
        }
    }

    private func save() {
        switch MemoryStore.shared.remember(content,
                                           target: target,
                                           importance: importance,
                                           source: initialContent.isEmpty ? "manual" : "message") {
        case .saved:
            dismiss()
        case .duplicate(let other):
            errorText = "已经记过了：\(other.trimmedContent)"
        case .tooLong(let limit):
            errorText = "一条最多 \(limit) 字，拆成几条更稳"
        case .empty:
            errorText = "内容不能为空"
        case .full(let message):
            errorText = message
        }
    }
}
