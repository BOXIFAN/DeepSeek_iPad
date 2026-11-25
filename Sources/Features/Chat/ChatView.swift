import SwiftUI

// MARK: - 对话区

/// 浮岛骨架下的对话流：没有导航栏，正文 660 居中，空态换成四张建议卡。
struct FloatingChatBody: View {
    var viewModel: ChatViewModel
    var onSuggestion: (String) -> Void
    var onOpenSettings: () -> Void
    /// 点开某条消息里的第几张图
    var onOpenImage: ([MessageImage], Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if viewModel.messages.isEmpty {
                        FloatingEmptyState(
                            errorText: viewModel.errorText,
                            onPick: onSuggestion,
                            onOpenSettings: onOpenSettings
                        )
                    } else {
                        ForEach(viewModel.messages) { message in
                            messageRow(message)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: viewModel.streamTick) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.currentConversation?.id) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatViewModel.DisplayMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message)
        case .assistant:
            assistantBody(message)
        }
    }

    private func userBubble(_ message: ChatViewModel.DisplayMessage) -> some View {
        HStack {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 6) {
                if !message.documents.isEmpty {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(message.documents) { document in
                            MessageDocumentChip(document: document)
                        }
                    }
                }
                if !message.images.isEmpty {
                    imageGrid(message.images)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 17))
                        .lineSpacing(4)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                }
            }
        }
    }

    /// 单张按原比例展示，多张排成两列方图；点击进入全屏。
    @ViewBuilder
    private func imageGrid(_ images: [MessageImage]) -> some View {
        if images.count == 1, let image = images.first, let ui = image.uiImage {
            let ratio = ui.size.width / max(ui.size.height, 1)
            let width: CGFloat = 232
            let height = min(300, max(120, width / max(ratio, 0.4)))
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    onOpenImage(images, 0)
                }
        } else {
            let side: CGFloat = images.count == 2 ? 148 : 104
            let columns = images.count == 2 ? 2 : 2
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 6), count: columns),
                      alignment: .trailing, spacing: 6) {
                ForEach(Array(images.enumerated()), id: \.element.id) { offset, image in
                    if let ui = image.uiImage {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onTapGesture {
                                onOpenImage(images, offset)
                            }
                    }
                }
            }
            .frame(maxWidth: side * 2 + 6)
        }
    }

    private func assistantBody(_ message: ChatViewModel.DisplayMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ContentBlock.grouped(message.blocks)) { block in
                BlockView(block: block)
            }

            if message.isStreaming && message.blocks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在思考…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = message.errorText {
                errorBanner(error)
            }

            if !message.isStreaming && !message.blocks.isEmpty {
                copyRow(message)
            }
        }
    }

    private func copyRow(_ message: ChatViewModel.DisplayMessage) -> some View {
        HStack(spacing: 18) {
            Button {
                let text = message.blocks.compactMap { block -> String? in
                    if case .text(_, let text, _) = block { return text }
                    return nil
                }.joined(separator: "\n\n")
                UIPasteboard.general.string = text
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 空态

private struct FloatingEmptyState: View {
    let errorText: String?
    let onPick: (String) -> Void
    let onOpenSettings: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private struct Suggestion: Identifiable {
        let id = UUID()
        let text: String
    }

    private let suggestions: [Suggestion] = [
        .init(text: "对比 @Observable 和 ObservableObject 该怎么选"),
        .init(text: "SSE 流式解析常见的断流原因有哪些"),
        .init(text: "给 iPad 双栏布局写一份断点规则"),
        .init(text: "用 SQLite 存会话，表结构怎么设计"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("鲸语")
                .font(.system(size: 34, weight: .semibold))
                .padding(.bottom, 8)

            Text("问一句，或者从下面挑一个开始。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.bottom, 28)

            if sizeClass == .regular {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(suggestions) { card($0) }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(suggestions) { card($0) }
                }
            }

            if let errorText {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(errorText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button("去设置", action: onOpenSettings)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.09))
                )
                .padding(.top, 18)
            }
        }
        .padding(.top, 36)
    }

    private func card(_ suggestion: Suggestion) -> some View {
        Button {
            onPick(suggestion.text)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(suggestion.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 悬浮输入条

struct FloatingComposer: View {
    @Binding var text: String
    var isStreaming: Bool
    /// 有没有待发的图片 / 文件：分别决定左侧两个附件图标是否高亮
    var hasImages: Bool
    var hasDocuments: Bool
    /// 文档上传解析中：发送要等文件就绪
    var isUploadingDocuments: Bool
    /// 有文件上传失败：先重试或删掉
    var hasFailedDocuments: Bool
    var focus: FocusState<Bool>.Binding
    var onSend: () -> Void
    var onStop: () -> Void
    var onPickImage: () -> Void
    var onPickFile: () -> Void

    private var hasAttachments: Bool { hasImages || hasDocuments }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments
    }

    private var sendEnabled: Bool {
        canSend && !isUploadingDocuments && !hasFailedDocuments
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 0) {
                Button(action: onPickImage) {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(hasImages ? Theme.accent : Color.secondary)
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加图片")

                Button(action: onPickFile) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(hasDocuments ? Theme.accent : Color.secondary)
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加文件")
            }

            TextField("给鲸语发消息", text: $text, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...6)
                .focused(focus)
                .padding(.vertical, 7)
                .padding(.leading, 6)

            Button {
                if isStreaming {
                    onStop()
                } else {
                    onSend()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(buttonColor))
            }
            .buttonStyle(.plain)
            .disabled(!isStreaming && !sendEnabled)
            .accessibilityLabel(isStreaming
                                ? "停止生成"
                                : (isUploadingDocuments ? "等文件上传完成"
                                   : (hasFailedDocuments ? "先处理上传失败的文件" : "发送")))
        }
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .padding(.leading, 4)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 22, y: 8)
    }

    private var buttonColor: Color {
        if isStreaming { return Color.secondary }
        return sendEnabled ? Theme.accent : Color.secondary.opacity(0.35)
    }
}

// MARK: - 思考强度

struct ThinkingEffortChip: View {
    @Binding var effort: ThinkingEffort

    var body: some View {
        Menu {
            ForEach(ThinkingEffort.allCases) { item in
                Button {
                    effort = item
                } label: {
                    if item == effort {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text("\(item.title) · \(item.detail)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "brain")
                    .font(.system(size: 10, weight: .medium))
                Text(effort.isEnabled ? "思考 · \(effort.title)" : "思考")
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(effort.isEnabled ? Theme.accent : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    effort.isEnabled
                        ? Theme.accent.opacity(0.1)
                        : Color.primary.opacity(0.045)
                )
            )
        }
    }
}

// MARK: - 技能选择

/// 输入条上的技能开关。作用范围是「接下来的请求」，不做全局常驻注入。
struct SkillPickerChip: View {
    let skills: [StoredSkill]
    var onToggle: (StoredSkill) -> Void

    private var enabledCount: Int {
        skills.filter(\.isEnabled).count
    }

    var body: some View {
        Menu {
            if skills.isEmpty {
                Text("还没有技能，去设置里添加")
            } else {
                ForEach(skills) { skill in
                    Button {
                        onToggle(skill)
                    } label: {
                        if skill.isEnabled {
                            Label(skill.name, systemImage: "checkmark")
                        } else {
                            Text(skill.name)
                        }
                    }
                }

                if enabledCount > 0 {
                    Divider()
                    Button("全部停用") {
                        for skill in skills where skill.isEnabled {
                            onToggle(skill)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bookmark")
                    .font(.system(size: 10, weight: .medium))
                Text(enabledCount == 0 ? "技能" : "技能 · \(enabledCount)")
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(enabledCount > 0 ? Theme.accent : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    enabledCount > 0
                        ? Theme.accent.opacity(0.1)
                        : Color.primary.opacity(0.045)
                )
            )
        }
    }
}

// MARK: - 模式开关

struct FloatingModeChip: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isOn ? Theme.accent : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isOn
                        ? Theme.accent.opacity(0.1)
                        : Color.primary.opacity(0.045)
                )
            )
        }
        .buttonStyle(.plain)
    }
}
